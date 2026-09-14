# frozen_string_literal: true

module AiCalls
  # Closes out one "stuck" CandidateAiCall by cross-checking Twilio
  # (authoritative for carrier/telephony state) and ElevenLabs (authoritative
  # for conversation state), per the plan's "Reconciliation" section --
  # catches calls whose webhook was evidently missed. Called by
  # AiCalls::ReconcileStuckCallsJob for every call past its per-status
  # threshold (see THRESHOLDS).
  #
  # Twilio Call resource `status` values assumed per Twilio's documented
  # API: queued/ringing/in-progress/completed/busy/failed/no-answer/canceled.
  # rubocop:disable Metrics/ClassLength
  class ReconcileCallService < ApplicationService
    THRESHOLDS = {
      'requested' => 1.minute,
      'queued' => 1.minute,
      'ringing' => 120.seconds,
      'processing' => 5.minutes
    }.freeze

    TWILIO_NOT_ANSWERED_REASONS = {
      'busy' => 'busy', 'no-answer' => 'no_answer', 'failed' => 'provider_failure', 'canceled' => 'provider_failure'
    }.freeze

    UNKNOWN_ELEVENLABS_STATUS_REVIEW_AFTER = 30.minutes

    def self.due?(candidate_ai_call, configuration: AiCalls::Configuration.new, now: Time.current)
      return in_progress_due?(candidate_ai_call, configuration:, now:) if candidate_ai_call.status == 'in_progress'

      threshold = THRESHOLDS[candidate_ai_call.status]
      threshold.present? && candidate_ai_call.updated_at <= now - threshold
    end

    def self.in_progress_due?(candidate_ai_call, configuration:, now:)
      buffer = 5.minutes
      threshold = configuration.max_call_duration_minutes.minutes + buffer
      candidate_ai_call.updated_at <= now - threshold
    end

    def initialize(candidate_ai_call:, request_id: SecureRandom.uuid, twilio_adapter: Providers::TwilioAdapter.new,
                   elevenlabs_adapter: Providers::ElevenlabsAdapter.new)
      @candidate_ai_call = candidate_ai_call
      @request_id = request_id
      @twilio_adapter = twilio_adapter
      @elevenlabs_adapter = elevenlabs_adapter
    end

    def call
      return @candidate_ai_call if @candidate_ai_call.terminal_status?

      elevenlabs_payload = fetch_elevenlabs_conversation
      return apply_elevenlabs_status!(elevenlabs_payload) if elevenlabs_payload&.conversation_id.present?
      return handle_elevenlabs_fetch_failure! if @elevenlabs_fetch_failed

      close_from_twilio_status!(fetch_twilio_status)
    end

    private

    # A transient ElevenLabs failure (timeout, 5xx, rate limit, or
    # ElevenLabs credentials unavailable) fetching a conversation that *is*
    # expected to exist must never be treated the same as "no conversation
    # exists" -- doing so would fall through to close_from_twilio_status!,
    # which (if Twilio reports 'completed') immediately makes the call
    # terminal via needs_manual_review!. Since reconciliation only ever
    # revisits non-terminal calls, that would permanently lose the chance to
    # ever fetch the transcript/analysis, over one flaky read. Retried
    # (a no-op) on the next job run, same grace window as an unrecognized
    # ElevenLabs status, before finally routing to manual review.
    def handle_elevenlabs_fetch_failure!
      return @candidate_ai_call if @candidate_ai_call.updated_at > Time.current - UNKNOWN_ELEVENLABS_STATUS_REVIEW_AFTER

      needs_manual_review!(
        'elevenlabs_fetch_failed',
        failure_message: 'Could not fetch the ElevenLabs conversation after repeated attempts'
      )
    end

    def fetch_elevenlabs_conversation
      return nil if @candidate_ai_call.elevenlabs_conversation_id.blank?

      PostCallWebhookPayload.new(
        @elevenlabs_adapter.fetch_conversation(conversation_id: @candidate_ai_call.elevenlabs_conversation_id)
      )
    rescue AiCallProviderUnavailableError, AiCallProviderRequestError
      @elevenlabs_fetch_failed = true
      nil
    end

    def fetch_twilio_status
      return nil if @candidate_ai_call.twilio_call_sid.blank?

      @twilio_adapter.fetch_call(call_sid: @candidate_ai_call.twilio_call_sid)['status']
    rescue AiCallProviderUnavailableError, AiCallProviderRequestError
      nil
    end

    # Branches on ElevenLabs' authoritative conversation status (see
    # AiCalls::ElevenlabsConversationStatus) rather than treating any
    # conversation record as a finished, answered call.
    def apply_elevenlabs_status!(payload)
      classification = ElevenlabsConversationStatus.classify(payload.status)
      case classification
      when :done then apply_elevenlabs_outcome!(payload)
      when :failed then close_from_twilio_status!(fetch_twilio_status)
      when :unknown then handle_unknown_elevenlabs_status!
      else sync_open_status!(elevenlabs_status: payload.status, local_status: classification)
      end
    end

    def apply_elevenlabs_outcome!(payload)
      mapping = OutcomeMapper.call(telephony_outcome: 'answered', extraction: payload.extraction)

      record_event!(observed_status: 'elevenlabs_conversation_found') do |call_record|
        call_record.update!(status: 'completed', outcome: mapping.outcome, outcome_reason: mapping.outcome_reason,
                            completed_at: Time.current, answered_at: call_record.answered_at || Time.current,
                            provider_status: payload.status, summary: payload.summary || call_record.summary,
                            extracted_data: payload.extraction || {})
        PersistTranscriptService.call(call_record:, payload:)
      end
    end

    # Leaves the call open (never completes/fails it) and synchronizes the
    # local `status` to reflect ElevenLabs' in-progress conversation state,
    # never regressing it (e.g. a late 'initiated' read must not move a
    # call already locally 'in_progress' back to 'ringing').
    def sync_open_status!(elevenlabs_status:, local_status:)
      order = CandidateAiCall::STATUSES
      return @candidate_ai_call unless order.index(local_status) > order.index(@candidate_ai_call.status)

      record_event!(observed_status: "elevenlabs_#{elevenlabs_status.tr('-', '_')}") do |call_record|
        call_record.update!(status: local_status, provider_status: elevenlabs_status)
      end
    end

    # Missing/malformed/unrecognized ElevenLabs status: retried on the next
    # job run (a no-op here) until the call has been stuck long enough that
    # it's no longer plausibly a transient read, at which point it's routed
    # to manual review instead of being retried indefinitely.
    def handle_unknown_elevenlabs_status!
      return @candidate_ai_call if @candidate_ai_call.updated_at > Time.current - UNKNOWN_ELEVENLABS_STATUS_REVIEW_AFTER

      needs_manual_review!('elevenlabs_status_unknown',
                           failure_message: 'ElevenLabs conversation status was missing or unrecognized')
    end

    def close_from_twilio_status!(twilio_status)
      return needs_manual_review_for_completed_without_conversation!(twilio_status) if twilio_status == 'completed'
      return @candidate_ai_call unless TWILIO_NOT_ANSWERED_REASONS.key?(twilio_status)

      reason = TWILIO_NOT_ANSWERED_REASONS.fetch(twilio_status)
      record_event!(observed_status: "twilio_#{twilio_status}") do |call_record|
        call_record.update!(status: 'failed', outcome: 'not_answered', outcome_reason: reason,
                            completed_at: Time.current, provider_status: twilio_status)
      end
    end

    def needs_manual_review_for_completed_without_conversation!(twilio_status)
      needs_manual_review!(
        'provider_completed_without_conversation',
        failure_message: 'Twilio reported the call as completed, but no ElevenLabs conversation could be found',
        provider_status: twilio_status
      )
    end

    def needs_manual_review!(observed_status, failure_message: nil, provider_status: nil)
      record_event!(observed_status:) do |call_record|
        call_record.update!(status: 'completed', outcome: nil, outcome_reason: 'needs_manual_review',
                            completed_at: Time.current, failure_message: failure_message || call_record.failure_message,
                            provider_status: provider_status || call_record.provider_status)
      end
    end

    def record_event!(observed_status:, &)
      event = {
        provider_code: 'elevenlabs', event_source: 'reconciliation', event_type: 'stuck_call_reconciled',
        event_key: "reconciliation:#{@candidate_ai_call.id}:#{observed_status}", occurred_at: Time.current,
        payload: { observed_status: }, request_id: @request_id
      }
      WebhookEventRecorder.new(candidate_ai_call: @candidate_ai_call, event:).call(&).candidate_ai_call
    end
  end
  # rubocop:enable Metrics/ClassLength
end

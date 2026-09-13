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
      return apply_elevenlabs_outcome!(elevenlabs_payload) if elevenlabs_payload&.conversation_id.present?

      close_from_twilio_status!(fetch_twilio_status)
    end

    private

    def fetch_elevenlabs_conversation
      return nil if @candidate_ai_call.elevenlabs_conversation_id.blank?

      PostCallWebhookPayload.new(
        @elevenlabs_adapter.fetch_conversation(conversation_id: @candidate_ai_call.elevenlabs_conversation_id)
      )
    rescue AiCallProviderUnavailableError, AiCallProviderRequestError
      nil
    end

    def fetch_twilio_status
      return nil if @candidate_ai_call.twilio_call_sid.blank?

      @twilio_adapter.fetch_call(call_sid: @candidate_ai_call.twilio_call_sid)['status']
    rescue AiCallProviderUnavailableError, AiCallProviderRequestError
      nil
    end

    def apply_elevenlabs_outcome!(payload)
      mapping = OutcomeMapper.call(telephony_outcome: 'answered', extraction: payload.extraction)

      record_event!(observed_status: 'elevenlabs_conversation_found') do |call_record|
        call_record.update!(status: 'completed', outcome: mapping.outcome, outcome_reason: mapping.outcome_reason,
                            completed_at: Time.current, answered_at: call_record.answered_at || Time.current)
        persist_transcript!(call_record, payload)
      end
    end

    def close_from_twilio_status!(twilio_status)
      return needs_manual_review!('provider_completed_without_conversation') if twilio_status == 'completed'
      return @candidate_ai_call unless TWILIO_NOT_ANSWERED_REASONS.key?(twilio_status)

      reason = TWILIO_NOT_ANSWERED_REASONS.fetch(twilio_status)
      record_event!(observed_status: "twilio_#{twilio_status}") do |call_record|
        call_record.update!(status: 'failed', outcome: 'not_answered', outcome_reason: reason,
                            completed_at: Time.current)
      end
    end

    def needs_manual_review!(observed_status)
      record_event!(observed_status:) do |call_record|
        call_record.update!(status: 'completed', outcome: nil, outcome_reason: 'needs_manual_review',
                            completed_at: Time.current)
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

    def persist_transcript!(call_record, payload)
      text = payload.transcript_text
      return if text.blank? || call_record.candidate_ai_call_transcript.present?

      call_record.create_candidate_ai_call_transcript!(
        transcript: text, recording_reference: payload.recording_reference, recorded_at: Time.current
      )
    end
  end
end

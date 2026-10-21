# frozen_string_literal: true

module AiCalls
  # Reads one open RoboCall call's status and records its result. RoboCall's
  # numeric call_status: 1 initiated (awaiting pickup), 2 answered, 3
  # congestion, 4 busy, 5 no answer, 6 hangup, 8 pushed to SIP (not yet
  # initiated). `dtmf` is the key the candidate pressed: 1 confirm, 2 cancel,
  # 3 callback.
  #
  # * 1 / 8 -- left open (queued) until the line is picked up or fails.
  # * 2 -- the call is in progress; it is closed as soon as a key press is
  #   seen, or DTMF_WAIT after it was first seen answered (the voice may still
  #   be playing, so the key press can arrive late).
  # * 3 / 4 / 5 / 6 -- not answered. RoboCall retries unanswered calls on its
  #   own (account Call Settings), so this is only final once the retry window
  #   has passed (RobocallConfiguration#retry_window_minutes); until then the
  #   call stays open, and an answered retry is still picked up. If the call
  #   was seen answered earlier, a later non-answered status is the candidate
  #   hanging up, and it is closed as answered.
  # * A call that is still not finished STUCK_MARGIN after the retry window,
  #   or whose status cannot be read, is sent to manual review.
  #
  # Every transition is recorded once through WebhookEventRecorder (an
  # idempotent event key), so repeated polls of an unchanged call do nothing.
  class PollRobocallCallService < ApplicationService
    ANSWERED = 2
    PENDING = [1, 8].freeze
    NOT_ANSWERED_REASONS = { 3 => 'provider_failure', 4 => 'busy', 5 => 'no_answer', 6 => 'hangup' }.freeze
    CALLBACK_KEY = '3'
    DTMF_WAIT = 3.minutes
    STUCK_MARGIN = 15.minutes

    def initialize(candidate_ai_call:, request_id: SecureRandom.uuid, adapter: Providers::RobocallAdapter.new,
                   configuration: RobocallConfiguration.new)
      @candidate_ai_call = candidate_ai_call
      @request_id = request_id
      @adapter = adapter
      @configuration = configuration
    end

    def call
      return @candidate_ai_call if @candidate_ai_call.terminal_status? || @candidate_ai_call.robocall_call_id.blank?

      status = fetch_status
      return give_up_if_stuck if status.nil?

      apply(status)
    end

    private

    # A provider hiccup is retried on the next run; only a call that has been
    # open far too long is closed for review.
    def fetch_status
      @adapter.fetch_call(call_id: @candidate_ai_call.robocall_call_id)
    rescue AiCallProviderUnavailableError, AiCallProviderRequestError
      nil
    end

    def apply(status)
      code = status.status_code
      return handle_answered(status) if code == ANSWERED
      return handle_not_answered(status) if NOT_ANSWERED_REASONS.key?(code)

      give_up_if_stuck
    end

    def handle_answered(status)
      finished_answering?(status) ? complete_answered(status) : mark_in_progress
    end

    # Not final while RoboCall may still retry. A call already seen answered
    # that now reads as not answered is the candidate hanging up.
    def handle_not_answered(status)
      return complete_answered(status) if @candidate_ai_call.answered_at.present?
      return @candidate_ai_call unless retry_window_over?

      complete_not_answered(status.status_code)
    end

    def retry_window_over?
      @candidate_ai_call.created_at <= Time.current - @configuration.retry_window_minutes.minutes
    end

    def finished_answering?(status)
      return true if status.dtmf.present?

      answered_at = @candidate_ai_call.answered_at
      answered_at.present? && answered_at <= Time.current - DTMF_WAIT
    end

    def mark_in_progress
      return @candidate_ai_call if @candidate_ai_call.status == 'in_progress'

      record_event!('answered') do |call_record|
        call_record.update!(status: 'in_progress', answered_at: call_record.answered_at || Time.current,
                            provider_status: 'answered')
      end
    end

    def complete_answered(status)
      mapping = OutcomeMapper.call(telephony_outcome: 'answered', extraction: extraction_for(status.dtmf))

      record_event!('completed', dtmf: status.dtmf) do |call_record|
        call_record.update!(
          status: 'completed', outcome: mapping.outcome, outcome_reason: mapping.outcome_reason,
          completed_at: Time.current, answered_at: call_record.answered_at || Time.current,
          provider_status: 'answered', extracted_data: { 'dtmf' => status.dtmf }.compact,
          callback_requested_at: (Time.current if status.dtmf == CALLBACK_KEY)
        )
      end
    end

    def extraction_for(dtmf)
      { human_answered: true, callback_requested: dtmf == CALLBACK_KEY, escalation_requested: false,
        call_resolved: true }
    end

    def complete_not_answered(code)
      reason = NOT_ANSWERED_REASONS.fetch(code)
      mapping = OutcomeMapper.call(telephony_outcome: reason)

      record_event!("not_answered_#{reason}") do |call_record|
        call_record.update!(status: 'failed', outcome: mapping.outcome, outcome_reason: mapping.outcome_reason,
                            completed_at: Time.current, provider_status: reason)
      end
    end

    def give_up_if_stuck
      return @candidate_ai_call if @candidate_ai_call.created_at > Time.current - stuck_after

      record_event!('stuck_needs_review') do |call_record|
        call_record.update!(status: 'completed', outcome: nil, outcome_reason: 'needs_manual_review',
                            completed_at: Time.current,
                            failure_message: 'RoboCall did not report a final result for this call')
      end
    end

    def stuck_after = @configuration.retry_window_minutes.minutes + STUCK_MARGIN

    def record_event!(observed_status, **payload, &)
      event = {
        provider_code: 'robocall', event_source: 'polling', event_type: 'call_status_polled',
        event_key: "robocall:#{@candidate_ai_call.id}:#{observed_status}", occurred_at: Time.current,
        payload: { observed_status: }.merge(payload.compact), request_id: @request_id
      }
      WebhookEventRecorder.new(candidate_ai_call: @candidate_ai_call, event:).call(&).candidate_ai_call
    end
  end
end

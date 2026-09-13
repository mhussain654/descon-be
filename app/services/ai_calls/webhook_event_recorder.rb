# frozen_string_literal: true

module AiCalls
  # Applies one webhook/tool-call/reconciliation event to a CandidateAiCall
  # idempotently, mirroring Payments::NotificationProcessor's shape: lock the
  # parent row, check for a duplicate event, and only run the caller's
  # state-changing block (and record the event) if it's genuinely new --
  # a replayed delivery is a no-op that returns the existing state.
  class WebhookEventRecorder < ApplicationService
    Result = Struct.new(:candidate_ai_call, :replayed, keyword_init: true)

    # `event` carries the CandidateAiCallEvent attributes to record:
    # provider_code:, event_source:, event_type:, event_key:, occurred_at:,
    # payload:, request_id:, and optionally actor:.
    def initialize(candidate_ai_call:, event:)
      @candidate_ai_call = candidate_ai_call
      @event = event
    end

    def call(&)
      CandidateAiCall.transaction { process(&) }
    end

    private

    def process
      call_record = CandidateAiCall.lock.find(@candidate_ai_call.id)
      return Result.new(candidate_ai_call: call_record, replayed: true) if duplicate_event?

      yield(call_record) if block_given?
      record_event!(call_record)
      Result.new(candidate_ai_call: call_record.reload, replayed: false)
    end

    def duplicate_event?
      CandidateAiCallEvent.exists?(provider_code: @event.fetch(:provider_code), event_key: @event.fetch(:event_key))
    end

    def record_event!(call_record)
      call_record.candidate_ai_call_events.create!(**@event)
    end
  end
end

# frozen_string_literal: true

module AiCalls
  # Claims one ElevenLabs tool-call invocation idempotently BEFORE running
  # its handler, then persists the result -- fixes
  # Api::V1::AiCalls::Elevenlabs::ToolCallsController's previous behavior of
  # running the handler first and recording an always-unique
  # (SecureRandom.uuid-keyed) event afterward, which meant every delivery
  # retry was treated as a brand-new event: a retried
  # verify_caller_identity call re-incremented `verification_attempts` and
  # could lock out a legitimate caller, and any mutating tool ran again
  # before anything about the first run was ever persisted.
  #
  # Idempotency key: candidate_ai_call id + tool_name + a digest of the
  # tool's own declared arguments. ElevenLabs' server-tool webhook payload
  # isn't documented to carry its own delivery/request id (unlike the
  # post-call webhook, which carries `data.conversation_id` --
  # see the "ASSUMED SHAPE" note on AiCalls::PostCallWebhookPayload); the
  # tool's own arguments are the most stable identifier actually available.
  # Two invocations of the same tool, on the same call, with the same
  # arguments are treated as one event; different arguments (e.g.
  # verify_caller_identity retried with a new reference number, or with a
  # CNIC now added) correctly produce a new one.
  #
  # Concurrency-safe the same way AiCalls::WebhookEventRecorder is: the
  # parent CandidateAiCall row is locked for the duration of the check +
  # handler execution + event write, so two concurrent deliveries of the
  # same call serialize instead of racing.
  class ClaimToolCallEventService
    Result = Struct.new(:payload, :replayed, keyword_init: true)

    def self.call(candidate_ai_call:, tool_name:, params:, request_id:, &handler)
      new(candidate_ai_call:, tool_name:, params:, request_id:).call(&handler)
    end

    def initialize(candidate_ai_call:, tool_name:, params:, request_id:)
      @candidate_ai_call = candidate_ai_call
      @tool_name = tool_name.to_s
      @params = params
      @request_id = request_id
    end

    def call
      CandidateAiCall.transaction do
        call_record = CandidateAiCall.lock.find(@candidate_ai_call.id)
        existing = existing_event(call_record)
        next Result.new(payload: existing.payload, replayed: true) if existing

        payload = yield(call_record)
        record_event!(call_record, payload)
        Result.new(payload:, replayed: false)
      end
    end

    private

    def event_key
      @event_key ||= "tool_call:#{@candidate_ai_call.id}:#{@tool_name}:#{arguments_digest}"
    end

    def arguments_digest
      normalized_params = @params.to_h.transform_keys(&:to_s).sort.to_h
      Digest::SHA256.hexdigest(normalized_params.to_json)
    end

    def existing_event(call_record)
      call_record.candidate_ai_call_events.find_by(provider_code: 'elevenlabs', event_key:)
    end

    def record_event!(call_record, payload)
      call_record.candidate_ai_call_events.create!(
        provider_code: 'elevenlabs', event_source: 'tool_call', event_type: @tool_name,
        event_key:, occurred_at: Time.current, payload:, request_id: @request_id
      )
    end
  end
end

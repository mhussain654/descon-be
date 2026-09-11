# frozen_string_literal: true

module AiCalls
  # Verifies and applies one ElevenLabs post-call webhook delivery: hard-
  # fails on an invalid signature, maps the structured extraction onto
  # outcome/outcome_reason via AiCalls::OutcomeMapper, and idempotently
  # records the event + updates the call (AiCalls::WebhookEventRecorder).
  #
  # `telephony_outcome` is always treated as 'answered' here -- if
  # ElevenLabs delivered a post-call payload at all, a conversation leg
  # existed. Calls that never connected (busy/no-answer/voicemail/carrier
  # failure) typically produce no ElevenLabs webhook at all; those are
  # caught by the reconciliation job cross-checking Twilio instead (see the
  # plan's "Reconciliation" section), not by this handler.
  class RecordPostCallWebhookService < ApplicationService
    def initialize(header:, raw_body:, params:, request_id:, adapter: Providers::ElevenlabsAdapter.new)
      @header = header
      @raw_body = raw_body
      @params = params
      @request_id = request_id
      @adapter = adapter
    end

    def call
      @adapter.verify_webhook_signature!(header: @header, raw_body: @raw_body)
      payload = PostCallWebhookPayload.new(@params)
      call_record = CandidateAiCall.find_by!(elevenlabs_conversation_id: payload.conversation_id)
      mapping = OutcomeMapper.call(telephony_outcome: 'answered', extraction: payload.extraction)

      recorder = WebhookEventRecorder.new(candidate_ai_call: call_record, event: event_for(payload:, mapping:))
      result = recorder.call { |record| apply_outcome!(record, payload:, mapping:) }
      result.candidate_ai_call
    end

    private

    def event_for(payload:, mapping:)
      {
        provider_code: 'elevenlabs', event_source: 'webhook', event_type: 'post_call_transcription',
        event_key: event_key_for(payload), occurred_at: Time.current, request_id: @request_id,
        payload: { outcome: mapping.outcome, outcome_reason: mapping.outcome_reason,
                   call_duration_seconds: payload.call_duration_seconds }.compact
      }
    end

    def event_key_for(payload)
      "elevenlabs:#{payload.conversation_id}:post_call_transcription"
    end

    def apply_outcome!(call_record, payload:, mapping:)
      call_record.update!(
        status: 'completed', outcome: mapping.outcome, outcome_reason: mapping.outcome_reason,
        completed_at: Time.current, answered_at: call_record.answered_at || Time.current
      )
      persist_transcript!(call_record, payload)
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

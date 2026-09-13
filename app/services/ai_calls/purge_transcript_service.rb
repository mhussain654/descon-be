# frozen_string_literal: true

module AiCalls
  # The only code path allowed to clear a CandidateAiCallTranscript's
  # content -- CandidateAiCallTranscript#assert_only_purge_fields_changed!
  # enforces this at the model level regardless, but this service is where
  # the purge is actually triggered from (AiCalls::PurgeExpiredTranscriptsJob).
  # Reuses WebhookEventRecorder for its lock+duplicate-event idempotency
  # rather than re-deriving it -- a concurrent job run racing this one finds
  # the same event_key already recorded and skips the purge.
  class PurgeTranscriptService < ApplicationService
    def initialize(candidate_ai_call_transcript:)
      @transcript = candidate_ai_call_transcript
    end

    def call
      return @transcript if @transcript.purged_at.present?

      WebhookEventRecorder.new(candidate_ai_call: @transcript.candidate_ai_call, event: event).call { purge! }
      @transcript.reload
    end

    private

    def purge!
      @transcript.update!(transcript: nil, recording_reference: nil, purged_at: Time.current)
    end

    def event
      {
        provider_code: 'system', event_source: 'retention_purge', event_type: 'transcript_purged',
        event_key: "retention:#{@transcript.candidate_ai_call_id}:transcript_purged", occurred_at: Time.current,
        payload: { candidate_ai_call_transcript_id: @transcript.id }
      }
    end
  end
end

# frozen_string_literal: true

module AiCalls
  # One shared transcript-persistence path for both the post-call webhook
  # (AiCalls::RecordPostCallWebhookService) and reconciliation
  # (AiCalls::ReconcileCallService) -- previously each had its own copy of
  # this method, and only the webhook copy stamped `expires_at`, leaving
  # transcripts recovered through reconciliation to never expire/purge (see
  # AiCalls::PurgeExpiredTranscriptsJob, which only selects rows whose
  # `expires_at` has passed).
  class PersistTranscriptService < ApplicationService
    def initialize(call_record:, payload:, configuration: AiCalls::Configuration.new)
      @call_record = call_record
      @payload = payload
      @configuration = configuration
    end

    def call
      text = @payload.transcript_text
      return if text.blank? || @call_record.candidate_ai_call_transcript.present?

      @call_record.create_candidate_ai_call_transcript!(
        transcript: text, recording_reference: @payload.recording_reference, recorded_at: Time.current,
        expires_at: @configuration.transcript_retention_days.days.from_now
      )
    end
  end
end

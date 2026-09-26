# frozen_string_literal: true

module AiCalls
  # Runs daily (config/recurring.yml) and clears the content of every
  # CandidateAiCallTranscript past its retention window -- see
  # AiCalls::PurgeTranscriptService and AiCalls::Configuration#transcript_retention_days.
  class PurgeExpiredTranscriptsJob < ApplicationJob
    queue_as :default

    def perform
      CandidateAiCallTranscript.where(purged_at: nil).where(expires_at: ..Time.current).find_each do |transcript|
        PurgeTranscriptService.call(candidate_ai_call_transcript: transcript)
      end
    end
  end
end

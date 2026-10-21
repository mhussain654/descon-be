# frozen_string_literal: true

module Admin
  module CandidateAiCalls
    # One admin-facing view of a CandidateAiCall -- never exposes the
    # transcript (see CandidateAiCallTranscript) or raw extracted_data
    # beyond the summary, only the lifecycle/outcome fields staff need to
    # track a call.
    class CandidateAiCallSerializer
      TRIGGERS = { 'workflow_stage_notification' => 'automatic', 'bulk_voice_call' => 'bulk' }.freeze

      # `voices` maps a RoboCall voice id to its RobocallVoice, so a list of
      # calls names every voice without one query per call.
      def initialize(candidate_ai_call, voices: {})
        @candidate_ai_call = candidate_ai_call
        @voices = voices
      end

      def as_json(*)
        identity_attributes.merge(outcome_attributes).merge(review_attributes).merge(timestamp_attributes)
      end

      private

      def identity_attributes
        {
          id: @candidate_ai_call.public_id,
          direction: @candidate_ai_call.direction,
          call_reason: @candidate_ai_call.call_reason,
          language_code: @candidate_ai_call.language_code,
          status: @candidate_ai_call.status,
          candidate: serialized_candidate,
          triggered_by: serialized_triggered_by
        }.merge(trigger_attributes)
      end

      # What started the call (manual, automatic stage call, bulk) and which
      # recorded voice was played.
      def trigger_attributes
        {
          trigger: TRIGGERS.fetch(@candidate_ai_call.call_reason, 'manual'),
          workflow_stage_code: @candidate_ai_call.workflow_stage_code,
          voice: serialized_voice
        }
      end

      def outcome_attributes
        {
          outcome: @candidate_ai_call.outcome,
          outcome_reason: @candidate_ai_call.outcome_reason,
          verification_status: @candidate_ai_call.verification_status,
          summary: @candidate_ai_call.summary
        }
      end

      # Review-resolution state for a needs_manual_review outcome (see
      # AiCalls::ResolveManualReviewService) -- always present, nil until a
      # review actually happens.
      def review_attributes
        {
          reviewed_by: serialized_reviewed_by,
          reviewed_at: @candidate_ai_call.reviewed_at&.utc&.iso8601,
          review_resolution: @candidate_ai_call.review_resolution,
          review_notes: @candidate_ai_call.review_notes
        }
      end

      def timestamp_attributes
        {
          started_at: @candidate_ai_call.started_at&.utc&.iso8601,
          answered_at: @candidate_ai_call.answered_at&.utc&.iso8601,
          completed_at: @candidate_ai_call.completed_at&.utc&.iso8601,
          created_at: @candidate_ai_call.created_at.utc.iso8601
        }
      end

      def serialized_candidate
        candidate = @candidate_ai_call.candidate
        return nil if candidate.blank?

        { id: candidate.public_id, full_name: candidate.full_name }
      end

      def serialized_voice
        voice_id = @candidate_ai_call.provider_voice_id
        return nil if voice_id.blank?

        voice = @voices[voice_id]
        { voice_id:, name_en: voice&.name_en, name_ur: voice&.name_ur }
      end

      def serialized_triggered_by
        actor = @candidate_ai_call.triggered_by
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end

      def serialized_reviewed_by
        actor = @candidate_ai_call.reviewed_by
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end
    end
  end
end

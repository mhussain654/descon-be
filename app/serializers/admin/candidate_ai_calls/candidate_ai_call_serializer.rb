# frozen_string_literal: true

module Admin
  module CandidateAiCalls
    # One admin-facing view of a CandidateAiCall -- never exposes the
    # transcript (see CandidateAiCallTranscript) or raw extracted_data
    # beyond the summary, only the lifecycle/outcome fields staff need to
    # track a call.
    class CandidateAiCallSerializer
      def initialize(candidate_ai_call)
        @candidate_ai_call = candidate_ai_call
      end

      def as_json(*)
        identity_attributes.merge(outcome_attributes).merge(timestamp_attributes)
      end

      private

      def identity_attributes
        {
          id: @candidate_ai_call.public_id,
          direction: @candidate_ai_call.direction,
          call_reason: @candidate_ai_call.call_reason,
          language_code: @candidate_ai_call.language_code,
          status: @candidate_ai_call.status,
          triggered_by: serialized_triggered_by
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

      def timestamp_attributes
        {
          started_at: @candidate_ai_call.started_at&.utc&.iso8601,
          answered_at: @candidate_ai_call.answered_at&.utc&.iso8601,
          completed_at: @candidate_ai_call.completed_at&.utc&.iso8601,
          created_at: @candidate_ai_call.created_at.utc.iso8601
        }
      end

      def serialized_triggered_by
        actor = @candidate_ai_call.triggered_by
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end
    end
  end
end

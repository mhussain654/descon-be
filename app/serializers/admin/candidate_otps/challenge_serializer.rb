# frozen_string_literal: true

module Admin
  module CandidateOtps
    # One sign-in code sent to a candidate: when, until when, where it stands,
    # and who sent it (nil when the candidate asked in the app). Never the
    # code or its digest.
    class ChallengeSerializer
      def initialize(challenge)
        @challenge = challenge
      end

      def as_json(*)
        {
          sent_at: @challenge.created_at.utc.iso8601,
          expires_at: @challenge.expires_at.utc.iso8601,
          status: @challenge.history_status,
          used_at: @challenge.consumed_at&.utc&.iso8601,
          wrong_attempts: @challenge.attempts,
          sent_by: sent_by
        }
      end

      private

      def sent_by
        actor = @challenge.sent_by
        actor && { id: actor.public_id, role: actor.role }
      end
    end
  end
end

# frozen_string_literal: true

module AiCalls
  module Tools
    class GetQvcStatus < VerifiedDataTool
      private

      def data
        attempt = assignment.candidate_qvc_attempts.latest_first.first
        return { status: 'not_scheduled' } if attempt.blank?

        ::CandidateWorkflows::QvcAttemptSerializer.new(attempt).as_json
      end
    end
  end
end

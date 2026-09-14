# frozen_string_literal: true

module AiCalls
  module Tools
    class GetProtectionStatus < VerifiedDataTool
      private

      def data
        serialized = ::CandidateWorkflows::ProtectionSerializer.new(assignment.candidate_protection_record).as_json
        serialized || { status: 'not_yet_scheduled' }
      end
    end
  end
end

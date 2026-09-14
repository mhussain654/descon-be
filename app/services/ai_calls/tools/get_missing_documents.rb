# frozen_string_literal: true

module AiCalls
  module Tools
    class GetMissingDocuments < VerifiedDataTool
      private

      def data
        progress = ::Candidates::ApplicationProgress::SummaryService.call(candidate:, assignment:)
        {
          missing_count: progress.documents.missing,
          completion_percentage: progress.documents.completion_percentage,
          blocking_requirements: progress.documents.blocking_requirements.map { |r| serialized(r) }
        }
      end

      def serialized(requirement)
        { requirement_code: requirement.requirement_code, name: requirement.name, reason: requirement.reason }
      end
    end
  end
end

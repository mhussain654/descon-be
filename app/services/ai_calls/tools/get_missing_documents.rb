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
        {
          requirement_code: requirement.requirement_code,
          name: requirement.name,
          reason: requirement.reason,
          reason_label: reason_label(requirement.reason)
        }
      end

      def reason_label(reason)
        I18n.t("api.ai_calls.labels.document_blocking_reasons.#{reason}", default: reason.to_s.humanize)
      end
    end
  end
end

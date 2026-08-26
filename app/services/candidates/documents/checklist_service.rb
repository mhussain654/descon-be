# frozen_string_literal: true

module Candidates
  module Documents
    class ChecklistService < ApplicationService
      def initialize(candidate:)
        @candidate = candidate
      end

      def call
        current_documents_by_type = current_documents.index_by(&:document_type_id)

        requirements.map do |requirement|
          ChecklistItemBuilder.call(
            requirement:,
            document: current_documents_by_type[requirement.document_type_id]
          )
        end
      end

      private

      def requirements
        @requirements ||= RequirementResolver.call(candidate: @candidate)
      end

      def current_documents
        assignment = @candidate.current_assignment
        return CandidateDocument.none if assignment.blank?

        assignment
          .candidate_documents
          .current_version
      end
    end
  end
end

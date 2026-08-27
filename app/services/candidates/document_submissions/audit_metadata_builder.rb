# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    class AuditMetadataBuilder < ApplicationService
      def initialize(candidate:, current_assignment:, required_requirements:, submission:, submitted_documents:)
        @candidate = candidate
        @current_assignment = current_assignment
        @required_requirements = required_requirements
        @submission = submission
        @submitted_documents = submitted_documents
      end

      def call
        {
          candidate_public_id: @candidate.public_id,
          candidate_assignment_public_id: @current_assignment.public_id,
          required_document_count: @required_requirements.count,
          required_requirement_codes: @required_requirements.map { |requirement| requirement.document_type.code },
          submission_public_id: @submission.public_id,
          submitted_document_count: @submitted_documents.count,
          submitted_requirement_codes: @submitted_documents.map { |document| document.document_type.code }
        }
      end
    end
  end
end

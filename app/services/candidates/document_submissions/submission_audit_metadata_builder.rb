# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    class SubmissionAuditMetadataBuilder < ApplicationService
      def initialize(candidate:, current_assignment:, required_requirements:, submission:, submitted_documents:)
        @candidate = candidate
        @current_assignment = current_assignment
        @required_requirements = required_requirements
        @submission = submission
        @submitted_documents = submitted_documents
      end

      def call
        AuditMetadataBuilder.call(
          candidate: @candidate,
          current_assignment: @current_assignment,
          required_requirements: @required_requirements,
          submission: @submission,
          submitted_documents: @submitted_documents
        )
      end
    end
  end
end

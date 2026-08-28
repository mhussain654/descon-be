# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    class SubmissionItemCreator < ApplicationService
      def initialize(submission:, documents:, requirements_by_document_type_id:)
        @submission = submission
        @documents = documents
        @requirements_by_document_type_id = requirements_by_document_type_id
      end

      def call
        @documents.each do |document|
          requirement = @requirements_by_document_type_id.fetch(document.document_type_id)
          @submission.submission_items.create!(
            candidate_document: document,
            requirement_code: requirement.document_type.code,
            required: requirement.required
          )
        end
      end
    end
  end
end

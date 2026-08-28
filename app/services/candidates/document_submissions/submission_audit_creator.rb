# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    class SubmissionAuditCreator < ApplicationService
      def initialize(candidate:, candidate_assignment:, submission:, request_id:, metadata:)
        @candidate = candidate
        @candidate_assignment = candidate_assignment
        @submission = submission
        @request_id = request_id
        @metadata = metadata
      end

      def call
        AuditEvent.create!(
          candidate: @candidate,
          candidate_assignment: @candidate_assignment,
          entity_type: 'CandidateDocumentSubmission',
          entity_id: @submission.id,
          action_code: 'candidate_documents_submitted',
          request_id: @request_id,
          metadata: @metadata,
          occurred_at: @submission.submitted_at
        )
      end
    end
  end
end

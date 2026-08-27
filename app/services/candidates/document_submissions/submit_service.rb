# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    class SubmitService < ApplicationService
      def initialize(candidate:, request_id:)
        @candidate = candidate
        @request_id = request_id
      end

      def call
        CandidateDocumentSubmission.transaction do
          lock_current_assignment!
          ensure_requirements_present!
          load_current_documents!
          ensure_submission_allowed!

          submit_documents!
          submission = create_submission!
          create_audit_event!(submission:)

          build_result(submission)
        end
      end

      private

      def build_result(submission) = ResultBuilder.call(progress: submission_progress, submission:)

      def create_submission!
        @current_assignment.candidate_document_submissions.create!(
          request_id: @request_id,
          submitted_at: Time.current
        )
      end

      def create_audit_event!(submission:)
        AuditEvent.create!(
          candidate: @candidate,
          candidate_assignment: @current_assignment,
          entity_type: 'CandidateDocumentSubmission',
          entity_id: submission.id,
          action_code: 'candidate_documents_submitted',
          request_id: @request_id,
          metadata: audit_metadata(submission),
          occurred_at: submission.submitted_at
        )
      end

      def audit_metadata(submission)
        AuditMetadataBuilder.call(
          candidate: @candidate,
          current_assignment: @current_assignment,
          required_requirements:,
          submission:,
          submitted_documents: documents_to_submit
        )
      end

      def documents_to_submit
        @documents_to_submit ||= @requirements.filter_map do |requirement|
          document = @current_documents_by_type[requirement.document_type_id]
          document if document&.status_code == 'uploaded'
        end.uniq
      end

      def ensure_requirements_present! = (raise NoDocumentRequirementsError if required_requirements.empty?)

      def ensure_submission_allowed!
        ReadinessValidator.call(
          documents_to_submit:,
          progress: current_progress
        )
      end

      def load_current_documents!
        @current_documents_by_type = @current_assignment
                                     .candidate_documents
                                     .current_version
                                     .where(document_type_id: @requirements.map(&:document_type_id))
                                     .lock
                                     .index_by(&:document_type_id)
      end

      def lock_current_assignment!
        assignment_id = @candidate.current_assignment&.id
        raise NoCurrentAssignmentError if assignment_id.blank?

        @current_assignment = CandidateAssignment.lock.find(assignment_id)
        @requirements = Candidates::Documents::RequirementResolver.call(
          candidate: @candidate,
          assignment: @current_assignment
        )
      end

      def required_requirements
        @required_requirements ||= @requirements.select(&:required)
      end

      def current_progress
        @current_progress ||= Candidates::ApplicationProgress::SummaryService.call(
          candidate: @candidate,
          assignment: @current_assignment,
          current_documents_by_type: @current_documents_by_type,
          requirements: @requirements
        )
      end

      def submission_progress
        Candidates::ApplicationProgress::SummaryService.call(
          candidate: @candidate,
          assignment: @current_assignment,
          current_documents_by_type: @current_documents_by_type,
          requirements: @requirements
        )
      end

      def submit_documents! = documents_to_submit.each { |document| submit_document!(document) }

      def submit_document!(document)
        document.update!(status_code: 'under_verification')
      end
    end
  end
end

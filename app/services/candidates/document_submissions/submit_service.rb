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
          prepare_submission!
          persist_submission!
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

      def create_audit_event!(submission:) = SubmissionAuditCreator.call(**submission_audit_arguments(submission))

      def documents_to_submit
        @documents_to_submit ||= @requirements.filter_map do |requirement|
          document = @current_documents_by_type[requirement.document_type_id]
          document if document&.status_code == 'uploaded'
        end.uniq
      end

      def ensure_requirements_present! = (raise NoDocumentRequirementsError if required_requirements.empty?)

      def ensure_submission_allowed! = ReadinessValidator.call(documents_to_submit:, progress: current_progress)

      def persist_submission!
        submit_documents!
        submission = create_submission!
        SubmissionItemCreator.call(
          submission:,
          documents: documents_to_submit,
          requirements_by_document_type_id:
        )
        create_audit_event!(submission:)
        build_result(submission)
      end

      def prepare_submission!
        lock_current_assignment!
        ensure_requirements_present!
        load_current_documents!
        ensure_submission_allowed!
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

      def required_requirements = @required_requirements ||= @requirements.select(&:required)

      def requirements_by_document_type_id
        @requirements_by_document_type_id ||= @requirements.index_by(&:document_type_id)
      end

      def current_progress = @current_progress ||= ProgressSummaryBuilder.call(**progress_summary_arguments)

      def progress_summary_arguments
        {
          candidate: @candidate,
          assignment: @current_assignment,
          current_documents_by_type: @current_documents_by_type,
          requirements: @requirements
        }
      end

      def submission_audit_arguments(submission)
        {
          candidate: @candidate,
          candidate_assignment: @current_assignment,
          submission:,
          request_id: @request_id,
          metadata: submission_audit_metadata(submission)
        }
      end

      def submission_audit_metadata(submission)
        SubmissionAuditMetadataBuilder.call(
          candidate: @candidate,
          current_assignment: @current_assignment,
          required_requirements:,
          submission:,
          submitted_documents: documents_to_submit
        )
      end

      def submission_progress = ProgressSummaryBuilder.call(**progress_summary_arguments)

      def submit_documents! = documents_to_submit.each { |document| submit_document!(document) }

      def submit_document!(document)
        document.update!(status_code: 'under_verification')
      end
    end
  end
end

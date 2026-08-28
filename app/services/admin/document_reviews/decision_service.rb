# frozen_string_literal: true

module Admin
  module DocumentReviews
    class DecisionService < ApplicationService
      DECISIONS = %w[verified rejected].freeze
      REJECTION_REASON_MAX_LENGTH = 500
      REJECTION_REASON_MIN_LENGTH = 10

      def initialize(actor:, decision:, document:, request_id:, rejection_reason: nil)
        @actor = actor
        @decision = decision.to_s
        @document = document
        @request_id = request_id
        @rejection_reason = rejection_reason.to_s.strip
      end

      def call
        CandidateDocument.transaction do
          document = lock_reviewable_document!
          apply_decision!(document)
          create_audit_event!(document)

          DecisionResult.new(
            document:,
            submission: document.candidate_document_submission,
            summary: SubmissionSummaryBuilder.call(submission: document.candidate_document_submission)
          )
        end
      end

      private

      def apply_decision!(document)
        validate_decision!
        validate_rejection_reason! if rejected?

        document.update!(decision_attributes)
      end

      def create_audit_event!(document)
        AuditEvent.create!(
          audit_attributes(document)
        )
      end

      def audit_action_code
        rejected? ? 'candidate_document_rejected' : 'candidate_document_verified'
      end

      def audit_attributes(document)
        {
          actor: @actor, candidate: document.candidate_assignment.candidate,
          candidate_assignment: document.candidate_assignment,
          entity_type: 'CandidateDocument', entity_id: document.id, action_code: audit_action_code,
          request_id: @request_id,
          metadata: audit_metadata(document),
          occurred_at: document.verified_at
        }
      end

      def audit_metadata(document)
        {
          actor_public_id: @actor.public_id,
          candidate_public_id: document.candidate_assignment.candidate.public_id,
          candidate_assignment_public_id: document.candidate_assignment.public_id,
          submission_public_id: document.candidate_document_submission.public_id,
          document_public_id: document.public_id,
          requirement_code: document.submission_item.requirement_code
        }
      end

      def decision_attributes
        {
          rejection_reason: rejected? ? @rejection_reason : nil,
          status_code: @decision,
          verified_at: Time.current,
          verified_by: @actor
        }
      end

      def lock_reviewable_document!
        document = CandidateDocument
                   .current_version
                   .joins(:submission_item)
                   .lock
                   .find_by(id: @document.id)
        raise CandidateDocumentNotFoundError if document.blank?
        raise DocumentAlreadyReviewedError if %w[verified rejected].include?(document.status_code)

        raise DocumentNotPendingReviewError unless document.status_code == 'under_verification'

        document
      end

      def rejected?
        @decision == 'rejected'
      end

      def validate_decision!
        raise ArgumentError, "unsupported decision: #{@decision}" unless DECISIONS.include?(@decision)
      end

      def validate_rejection_reason!
        raise RejectionReasonRequiredError if @rejection_reason.blank?
        raise RejectionReasonInvalidError if @rejection_reason.length < REJECTION_REASON_MIN_LENGTH
        raise RejectionReasonInvalidError if @rejection_reason.length > REJECTION_REASON_MAX_LENGTH
        raise RejectionReasonInvalidError if sanitized_rejection_reason != @rejection_reason
      end

      def sanitized_rejection_reason
        ActionController::Base.helpers.strip_tags(@rejection_reason)
      end
    end
  end
end

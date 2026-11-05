# frozen_string_literal: true

module Admin
  module CandidateBankDetails
    # Records a staff decision on a candidate's current bank details: verified,
    # or rejected with a reason the candidate sees (the same reason rules as a
    # document rejection). Only details still awaiting review can be decided.
    # A verification may complete the candidate's document review, so it moves
    # the workflow on like a document decision does.
    class DecisionService < ApplicationService
      DECISIONS = %w[verified rejected].freeze
      REASON_LENGTH = (DocumentReviews::DecisionService::REJECTION_REASON_MIN_LENGTH..
                       DocumentReviews::DecisionService::REJECTION_REASON_MAX_LENGTH)

      def initialize(actor:, candidate:, decision:, request_id:, rejection_reason: nil)
        @actor = actor
        @candidate = candidate
        @decision = decision.to_s
        @request_id = request_id
        @rejection_reason = rejection_reason.to_s.strip
      end

      def call
        raise ArgumentError, "unsupported decision: #{@decision}" unless DECISIONS.include?(@decision)

        CandidateBankDetail.transaction do
          bank_detail = lock_reviewable_bank_detail!
          apply_decision!(bank_detail)
          create_audit_event!(bank_detail)
          schedule_rejection_sms!(bank_detail) if rejected?
          advance_workflow!
          bank_detail
        end
      end

      private

      def rejected? = @decision == 'rejected'

      def apply_decision!(bank_detail)
        validate_rejection_reason! if rejected?
        bank_detail.update!(status_code: @decision, rejection_reason: rejected? ? @rejection_reason : nil,
                            reviewed_at: Time.current, reviewed_by: @actor)
      end

      def lock_reviewable_bank_detail!
        assignment = @candidate.current_assignment
        raise CandidateBankDetailNotFoundError if assignment.blank?

        bank_detail = CandidateBankDetail.current_version.lock.find_by(candidate_assignment: assignment)
        raise CandidateBankDetailNotFoundError if bank_detail.blank?
        raise DocumentAlreadyReviewedError unless bank_detail.status_code == 'submitted'

        bank_detail
      end

      def validate_rejection_reason!
        raise RejectionReasonRequiredError if @rejection_reason.blank?
        raise RejectionReasonInvalidError unless REASON_LENGTH.cover?(@rejection_reason.length)
        raise RejectionReasonInvalidError unless plain_text?(@rejection_reason)
      end

      def plain_text?(text) = ActionController::Base.helpers.strip_tags(text) == text

      def create_audit_event!(bank_detail)
        AuditEvent.create!(
          actor: @actor, candidate: @candidate, candidate_assignment: bank_detail.candidate_assignment,
          entity_type: 'CandidateBankDetail', entity_id: bank_detail.id,
          action_code: rejected? ? 'candidate_bank_detail_rejected' : 'candidate_bank_detail_verified',
          request_id: @request_id, occurred_at: bank_detail.reviewed_at,
          metadata: { actor_public_id: @actor.public_id, candidate_public_id: @candidate.public_id,
                      bank_detail_public_id: bank_detail.public_id }
        )
      end

      # Same message as a rejected document, naming the bank details.
      def schedule_rejection_sms!(bank_detail)
        assignment = bank_detail.candidate_assignment
        locale = CandidateSms::ScheduleDelivery.locale_for(@candidate)
        CandidateSms::ScheduleDelivery.call(
          assignment:, message_code: 'document_rejected', dedupe_key: "bank_detail_rejected:#{bank_detail.id}",
          variables: { document: I18n.t('candidate_bank_details.document_name', locale:) }
        )
      end

      def advance_workflow!
        CandidateWorkflows::AutomaticTransitionService.call(
          candidate: @candidate, event: :documents_reviewed, actor: @actor, request_id: @request_id
        )
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Records a staff reviewer's decision to verify a submitted candidate
      # document.
      class DocumentVerificationsController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_review_not_allowed

        # Verifies the given submitted document; deduplicated via the
        # decision fingerprint so a retried request does not double-verify.
        def create
          authorize candidate_document, :verify?, policy_class: ::Admin::CandidateDocumentPolicy

          render_idempotent_response(
            scope: 'admin.candidate_documents.verifications.create',
            subject: current_user,
            fingerprint: decision_fingerprint,
            required: true
          ) do
            success_payload(data: serialized_result, status: :created)
          end
        end

        private

        # Loads the current version of the submitted document named in the
        # route, raising if no matching document exists.
        def candidate_document
          @candidate_document ||= begin
            document = CandidateDocument.current_version.joins(:submission_item).find_by(
              public_id: params.expect(:candidate_document_id)
            )
            raise CandidateDocumentNotFoundError if document.blank?

            document
          end
        end

        # Builds the idempotency-key fingerprint for this verification
        # decision.
        def decision_fingerprint
          ::Admin::DocumentReviews::DecisionFingerprint.call(
            action: 'verified',
            document: candidate_document,
            request:,
            issued_on: verification_params[:issued_on],
            expires_on: verification_params[:expires_on]
          )
        end

        # Optional -- only meaningful for an OCR-supported document type
        # (passport/CNIC front/back/next-of-kin-CNIC); harmless to accept
        # generically since CandidateDocument already has these columns for
        # other purposes (e.g. police_character).
        def verification_params
          params.permit(:issued_on, :expires_on)
        end

        # Executes the verification via DecisionService and serializes the
        # created result for the response.
        def serialized_result
          result = ::Admin::DocumentReviews::DecisionService.call(
            actor: current_user,
            decision: 'verified',
            document: candidate_document,
            request_id: request.request_id,
            issued_on: verification_params[:issued_on],
            expires_on: verification_params[:expires_on]
          )

          ::Admin::DocumentReviewDecisionSerializer.new(result).as_json
        end

        # Renders a not-allowed error when Pundit denies this review action.
        def render_review_not_allowed
          render_api_error(ReviewNotAllowedError.new)
        end
      end
    end
  end
end

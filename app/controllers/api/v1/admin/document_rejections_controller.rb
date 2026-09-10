# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Records a staff reviewer's decision to reject a submitted candidate
      # document, with a reason.
      class DocumentRejectionsController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_review_not_allowed

        # Rejects the given submitted document; deduplicated via the
        # decision fingerprint so a retried request does not double-reject.
        def create
          authorize candidate_document, :reject?, policy_class: ::Admin::CandidateDocumentPolicy

          render_idempotent_response(
            scope: 'admin.candidate_documents.rejections.create',
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

        # Builds the idempotency-key fingerprint for this rejection
        # decision.
        def decision_fingerprint
          ::Admin::DocumentReviews::DecisionFingerprint.call(
            action: 'rejected',
            document: candidate_document,
            rejection_reason: rejection_reason,
            request:
          )
        end

        # Reads the submitted rejection reason.
        def rejection_reason
          rejection_params[:reason]
        end

        # Permits the rejection reason param from the request body.
        def rejection_params
          params.expect(rejection: %i[reason])
        end

        # Executes the rejection via DecisionService and serializes the
        # created result for the response.
        def serialized_result
          result = ::Admin::DocumentReviews::DecisionService.call(
            actor: current_user,
            decision: 'rejected',
            document: candidate_document,
            rejection_reason:,
            request_id: request.request_id
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

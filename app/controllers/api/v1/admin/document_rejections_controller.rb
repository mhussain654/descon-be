# frozen_string_literal: true

module Api
  module V1
    module Admin
      class DocumentRejectionsController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_review_not_allowed

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

        def candidate_document
          @candidate_document ||= begin
            document = CandidateDocument.current_version.joins(:submission_item).find_by(
              public_id: params.expect(:candidate_document_id)
            )
            raise CandidateDocumentNotFoundError if document.blank?

            document
          end
        end

        def decision_fingerprint
          ::Admin::DocumentReviews::DecisionFingerprint.call(
            action: 'rejected',
            document: candidate_document,
            rejection_reason: rejection_reason,
            request:
          )
        end

        def rejection_reason
          rejection_params[:reason]
        end

        def rejection_params
          params.expect(rejection: %i[reason])
        end

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

        def render_review_not_allowed
          render_api_error(ReviewNotAllowedError.new)
        end
      end
    end
  end
end

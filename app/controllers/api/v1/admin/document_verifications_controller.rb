# frozen_string_literal: true

module Api
  module V1
    module Admin
      class DocumentVerificationsController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_review_not_allowed

        def create
          authorize candidate_document, :verify?, policy_class: ::Admin::CandidateDocumentPolicy

          render_idempotent_response(
            scope: 'admin.candidate_documents.verifications.create',
            subject: current_user,
            fingerprint: decision_fingerprint
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
            action: 'verified',
            document: candidate_document,
            request:
          )
        end

        def serialized_result
          result = ::Admin::DocumentReviews::DecisionService.call(
            actor: current_user,
            decision: 'verified',
            document: candidate_document,
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

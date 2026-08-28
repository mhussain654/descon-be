# frozen_string_literal: true

module Api
  module V1
    module Admin
      class DocumentAccessesController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_document_access_forbidden

        def create
          authorize candidate_document, :access?, policy_class: ::Admin::CandidateDocumentPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::Admin::DocumentAccessSerializer.new(access_result).as_json)
        end

        private

        def access_result
          @access_result ||= ::Admin::DocumentReviews::AccessService.call(
            actor: current_user,
            document: candidate_document,
            request_id: request.request_id
          )
        end

        def candidate_document
          @candidate_document ||= begin
            document = CandidateDocument
                       .current_version
                       .joins(:submission_item)
                       .includes(:submission_item, candidate_assignment: :candidate)
                       .find_by(public_id: params.expect(:candidate_document_id))
            raise CandidateDocumentNotFoundError if document.blank?

            document
          end
        end

        def render_document_access_forbidden
          render_api_error(DocumentAccessForbiddenError.new)
        end
      end
    end
  end
end

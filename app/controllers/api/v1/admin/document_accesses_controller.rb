# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Issues a short-lived signed URL so staff can view a candidate's
      # uploaded document file, and records the access for audit purposes.
      class DocumentAccessesController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_document_access_forbidden

        # Grants (and returns) time-limited access to the submitted
        # document's file; never cached by the browser.
        def create
          authorize candidate_document, :access?, policy_class: ::Admin::CandidateDocumentPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::Admin::DocumentAccessSerializer.new(access_result).as_json)
        end

        private

        # Requests and memoizes the signed access result from the
        # document-access service, which also logs the access for audit
        # purposes.
        def access_result
          @access_result ||= ::Admin::DocumentReviews::AccessService.call(
            actor: current_user,
            document: candidate_document,
            request_id: request.request_id
          )
        end

        # Loads the current version of the submitted document named in the
        # route, raising if no matching document exists.
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

        # Renders a forbidden-access error when Pundit denies this action.
        def render_document_access_forbidden
          render_api_error(DocumentAccessForbiddenError.new)
        end
      end
    end
  end
end

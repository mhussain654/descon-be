# frozen_string_literal: true

module Api
  module V1
    module Admin
      # The documents a candidate has uploaded on their current assignment,
      # whether or not they have submitted them, so support can check what they
      # sent. View only: approving and rejecting happen only on submitted
      # documents (document reviews). Developer-only.
      class CandidateUploadedDocumentsController < ProtectedStaffController
        rescue_from Pundit::NotAuthorizedError, with: :render_document_access_forbidden

        def index
          authorize :uploaded_document, :index?, policy_class: ::Admin::UploadedDocumentPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: documents.map { |document| ::Admin::UploadedDocumentSerializer.new(document).as_json })
        end

        # A short-lived link to one file of the document (audited, like the
        # review's own document access).
        def access
          authorize :uploaded_document, :access?, policy_class: ::Admin::UploadedDocumentPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::Admin::DocumentAccessSerializer.new(access_result).as_json)
        end

        private

        def access_result
          document = documents.find_by(public_id: params.expect(:id)) || raise(CandidateDocumentNotFoundError)
          ::Admin::DocumentReviews::AccessService.call(
            actor: current_user, document:, request_id: request.request_id, file_id: params[:file_id].presence
          )
        end

        def documents
          assignment = candidate.current_assignment
          return ::CandidateDocument.none if assignment.nil?

          assignment.candidate_documents.current_version
                    .includes(:document_type, :files, :submission_item).order(:uploaded_at, :id)
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidatePolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def render_document_access_forbidden
          render_api_error(DocumentAccessForbiddenError.new)
        end
      end
    end
  end
end

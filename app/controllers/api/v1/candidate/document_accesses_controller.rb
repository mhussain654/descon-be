# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets the logged-in candidate retrieve a short-lived signed URL for
      # one of their own already-uploaded documents, so they can always see
      # what they submitted.
      class DocumentAccessesController < ProtectedController
        # Records that the candidate accessed their document and returns the access details.
        def create
          authorize current_candidate, :access?, policy_class: ::Candidates::DocumentPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::Candidates::Documents::AccessSerializer.new(access_result).as_json)
        end

        private

        # Requests and memoizes the signed access result from the document access service.
        def access_result
          @access_result ||= ::Candidates::Documents::AccessService.call(
            actor: nil,
            candidate: current_candidate,
            document: document,
            request_id: request.request_id,
            disposition: disposition,
            file_id: params[:file_id].presence
          )
        end

        # Reads and validates the optional requested disposition ('inline' to view in the
        # browser, 'attachment' to prompt a device download) -- defaults to 'inline' so
        # existing callers that don't send it keep their current behavior.
        def disposition
          value = params[:disposition].presence || 'inline'
          unless ::Candidates::Documents::AccessService::DISPOSITIONS.include?(value)
            raise InvalidQueryParameterError.new(field: 'disposition')
          end

          value
        end

        # Finds the candidate's own document named in the route, raising a 404 if not found --
        # scoped to their current assignment's current document versions, so a candidate can
        # never reach another candidate's document, an unrelated document, or a superseded version.
        def document
          @document ||= begin
            found = current_assignment_documents&.find_by(public_id: params.expect(:document_id))
            raise NotFoundError if found.blank?

            found
          end
        end

        def current_assignment_documents
          current_candidate.current_assignment&.candidate_documents&.current_version
        end
      end
    end
  end
end

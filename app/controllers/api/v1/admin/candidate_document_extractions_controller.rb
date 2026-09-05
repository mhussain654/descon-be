# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Read-only: the latest OCR extraction attempt for a document
      # (MPS-404), feeding the document-review UI's pre-filled
      # issue/expiry inputs. Same submitted-document scoping as
      # DocumentVerificationsController/DocumentRejectionsController.
      class CandidateDocumentExtractionsController < ProtectedStaffController
        def show
          authorize candidate_document, :extraction?, policy_class: ::Admin::CandidateDocumentPolicy

          render_success(data: ::Admin::DocumentExtractionSerializer.new(latest_extraction).as_json)
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

        def latest_extraction
          candidate_document.document_extractions.latest_first.first
        end
      end
    end
  end
end

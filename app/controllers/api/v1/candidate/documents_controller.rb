# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate view their required-document checklist and upload documents against it.
      class DocumentsController < ProtectedController
        # Returns the current candidate's document checklist, each item annotated with its review status.
        def index
          authorize current_candidate, policy_class: ::Candidates::DocumentPolicy

          checklist_items = ::Candidates::Documents::ChecklistService.call(candidate: current_candidate)
          render_success(data: checklist_items.map { |item| ::Candidates::DocumentSerializer.new(item).as_json })
        end

        # Uploads a document -- one or more files (`files[]`, each with an optional
        # `side_code`) -- against a checklist requirement; idempotent per Idempotency-Key,
        # fingerprinted on the files/side codes/requirement/issue date to detect a differing
        # retried request. The legacy single `file` field is still accepted as a one-file upload.
        def create
          authorize current_candidate, policy_class: ::Candidates::DocumentPolicy

          render_idempotent_response(
            scope: 'candidate.documents.create',
            subject: current_candidate,
            fingerprint: upload_fingerprint
          ) do
            upload_payload
          end
        end

        private

        # Runs the upload service and builds the created-document success payload.
        def upload_payload
          checklist_item = ::Candidates::Documents::UploadService.call(**upload_service_arguments)

          success_payload(
            data: ::Candidates::DocumentSerializer.new(checklist_item).as_json,
            status: :created
          )
        end

        # Computes a fingerprint of the upload request (when an Idempotency-Key was supplied) so a
        # replayed key against a materially different upload can be detected.
        def upload_fingerprint
          return if request.headers['Idempotency-Key'].blank?

          ::Candidates::Documents::UploadFingerprint.call(
            request:,
            uploaded_files:,
            requirement_code: document_params[:requirement_code],
            issued_on: document_params[:issued_on]
          )
        end

        # Strong-params the document upload fields (requirement code, files with their side
        # codes or the legacy single file, and validity dates).
        def document_params
          @document_params ||= params.expect(
            candidate_document: [:requirement_code, :file, :issued_on, :expires_on, { files: [%i[file side_code]] }]
          )
        end

        # The uploaded file set as `{ file:, side_code: }` entries, from `files[]` or, for
        # older clients, the single `file` field.
        def uploaded_files
          @uploaded_files ||=
            if document_params[:files].present?
              document_params[:files].map { |entry| { file: entry[:file], side_code: entry[:side_code] } }
            elsif document_params[:file].present?
              [{ file: document_params[:file], side_code: nil }]
            else
              []
            end
        end

        # Builds the argument hash passed to the document upload service.
        def upload_service_arguments
          {
            candidate: current_candidate,
            uploaded_files:,
            requirement_code: document_params[:requirement_code],
            request_id: request.request_id,
            pcc_attributes:
          }
        end

        # Builds the police-clearance-certificate-specific attributes (issue/expiry dates) for the upload service.
        def pcc_attributes
          {
            issued_on: document_params[:issued_on],
            expires_on: document_params[:expires_on],
            expires_on_supplied: document_params.key?(:expires_on)
          }
        end
      end
    end
  end
end

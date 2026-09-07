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

        # Uploads a document against a checklist requirement; idempotent per Idempotency-Key,
        # fingerprinted on the file/requirement/issue date to detect a differing retried request.
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
            uploaded_file: document_params[:file],
            requirement_code: document_params[:requirement_code],
            issued_on: document_params[:issued_on]
          )
        end

        # Strong-params the document upload fields (requirement code, file, and validity dates).
        def document_params
          params.expect(candidate_document: %i[requirement_code file issued_on expires_on])
        end

        # Builds the argument hash passed to the document upload service.
        def upload_service_arguments
          {
            candidate: current_candidate,
            uploaded_file: document_params[:file],
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

# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class DocumentsController < ProtectedController
        def index
          authorize current_candidate, policy_class: ::Candidates::DocumentPolicy

          checklist_items = ::Candidates::Documents::ChecklistService.call(candidate: current_candidate)
          render_success(data: checklist_items.map { |item| ::Candidates::DocumentSerializer.new(item).as_json })
        end

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

        def upload_payload
          checklist_item = ::Candidates::Documents::UploadService.call(**upload_service_arguments)

          success_payload(
            data: ::Candidates::DocumentSerializer.new(checklist_item).as_json,
            status: :created
          )
        end

        def upload_fingerprint
          return if request.headers['Idempotency-Key'].blank?

          ::Candidates::Documents::UploadFingerprint.call(
            request:,
            uploaded_file: document_params[:file],
            requirement_code: document_params[:requirement_code],
            issued_on: document_params[:issued_on]
          )
        end

        def document_params
          params.expect(candidate_document: %i[requirement_code file issued_on expires_on])
        end

        def upload_service_arguments
          {
            candidate: current_candidate,
            uploaded_file: document_params[:file],
            requirement_code: document_params[:requirement_code],
            request_id: request.request_id,
            pcc_attributes:
          }
        end

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

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
          checklist_item = ::Candidates::Documents::UploadService.call(
            candidate: current_candidate,
            uploaded_file: document_params[:file],
            requirement_code: document_params[:requirement_code],
            request_id: request.request_id
          )

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
            requirement_code: document_params[:requirement_code]
          )
        end

        def document_params
          params.expect(candidate_document: %i[requirement_code file])
        end
      end
    end
  end
end

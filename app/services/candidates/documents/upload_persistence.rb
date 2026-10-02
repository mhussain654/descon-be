# frozen_string_literal: true

module Candidates
  module Documents
    # Saves an inspected, validated file set as the requirement's new current
    # document version (superseding the previous one when replacement is
    # allowed). `files` are `{ side_code:, details: UploadedFileDetails, blob: }`
    # in upload order.
    class UploadPersistence < ApplicationService
      def initialize(candidate:, requirement:, files:, context:)
        @candidate = candidate
        @requirement = requirement
        @files = files
        @request_id = context[:request_id]
        @issued_on = context[:issued_on]
      end

      def call
        uploaded_document = nil

        CandidateDocument.transaction { uploaded_document = persist_document }
        enqueue_extraction(uploaded_document)

        uploaded_document
      end

      private

      # Enqueued after the transaction commits (MPS-404), never inside it --
      # a job dequeued before commit would find no row. Only passport/CNIC
      # front/back/next-of-kin-CNIC (DocumentType#supports_ocr_extraction?)
      # ever get OCR; every other document type is unaffected.
      def enqueue_extraction(document)
        return unless document.document_type.supports_ocr_extraction?

        Candidates::Documents::ExtractDatesJob.perform_later(document.id)
      end

      def persist_document
        current_assignment.with_lock do
          current_document = locked_current_document
          validate_replacement!(current_document)
          supersede_current_document!(current_document)
          uploaded_document = create_document!
          create_audit_event!(uploaded_document:, replaced: current_document.present?)
          uploaded_document
        end
      end

      def current_assignment
        @current_assignment ||= @candidate.current_assignment
      end

      def locked_current_document
        current_assignment.candidate_documents.current_version.lock.find_by(document_type: @requirement.document_type)
      end

      def validate_replacement!(current_document)
        return if current_document.blank? || replacement_allowed?(current_document)

        raise ReplacementNotAllowedError
      end

      def replacement_allowed?(current_document)
        current_document.replacement_allowed? || expired_pcc_replacement?(current_document)
      end

      def supersede_current_document!(current_document)
        return if current_document.blank?

        current_document.update!(superseded_at: Time.current)
      end

      def create_document!
        document = current_assignment.candidate_documents.new(document_attributes)
        @files.each.with_index(1) { |file, position| build_file(document, file, position) }
        document.save!
        document
      end

      def build_file(document, file, position)
        details = file.fetch(:details)
        document_file = document.files.build(
          side_code: file[:side_code], position:, original_filename: details.filename,
          content_type: details.content_type, byte_size: details.byte_size, checksum_sha256: details.checksum_sha256
        )
        document_file.file.attach(file.fetch(:blob))
      end

      def document_attributes
        {
          document_type: @requirement.document_type,
          status_code: 'uploaded',
          uploaded_at: Time.current,
          issued_on: @issued_on
        }
      end

      def create_audit_event!(uploaded_document:, replaced:)
        AuditEvent.create!(
          candidate: @candidate,
          candidate_assignment: current_assignment,
          entity_type: 'CandidateDocument',
          entity_id: uploaded_document.id,
          action_code: replaced ? 'candidate_document_replaced' : 'candidate_document_uploaded',
          request_id: @request_id,
          metadata: audit_metadata(uploaded_document),
          occurred_at: Time.current
        )
      end

      def audit_metadata(uploaded_document)
        {
          candidate_public_id: @candidate.public_id,
          document_public_id: uploaded_document.public_id,
          requirement_code: @requirement.document_type.code,
          file_count: @files.size,
          side_codes: @files.filter_map { |file| file[:side_code] }
        }.merge(pcc_audit_metadata(uploaded_document))
      end

      def pcc_audit_metadata(uploaded_document)
        return {} unless uploaded_document.police_character?

        {
          issued_on: uploaded_document.issued_on.iso8601,
          expires_on: uploaded_document.expires_on.iso8601
        }
      end

      def expired_pcc_replacement?(current_document)
        current_document.police_character? && current_document.compliance_status == 'expired'
      end
    end
  end
end

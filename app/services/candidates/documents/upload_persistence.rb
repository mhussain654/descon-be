# frozen_string_literal: true

module Candidates
  module Documents
    class UploadPersistence < ApplicationService
      def initialize(candidate:, requirement:, file_details:, blob:, request_id:)
        @candidate = candidate
        @requirement = requirement
        @file_details = file_details
        @blob = blob
        @request_id = request_id
      end

      def call
        uploaded_document = nil

        CandidateDocument.transaction { uploaded_document = persist_document }

        uploaded_document
      end

      private

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
        return if current_document.blank? || current_document.replacement_allowed?

        raise ReplacementNotAllowedError
      end

      def supersede_current_document!(current_document)
        return if current_document.blank?

        current_document.update!(superseded_at: Time.current)
      end

      def create_document!
        document = current_assignment.candidate_documents.new(document_attributes)
        document.file.attach(@blob)
        document.save!
        document
      end

      def document_attributes
        {
          document_type: @requirement.document_type,
          status_code: 'uploaded',
          original_filename: @file_details.filename,
          content_type: @file_details.content_type,
          byte_size: @file_details.byte_size,
          checksum_sha256: @file_details.checksum_sha256,
          uploaded_at: Time.current
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
          requirement_code: @requirement.document_type.code
        }
      end
    end
  end
end

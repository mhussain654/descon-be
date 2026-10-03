# frozen_string_literal: true

module Candidates
  module Documents
    class ChecklistItemBuilder < ApplicationService
      def initialize(requirement:, document:)
        @requirement = requirement
        @document = document
      end

      def call
        ChecklistItem.new(
          requirement_code: @requirement.document_type.code,
          name: @requirement.document_type.name_for,
          required: @requirement.required,
          **configuration,
          status: current_status,
          replacement_allowed: replacement_allowed?,
          document: serialized_document
        )
      end

      private

      def configuration
        {
          display_position: @requirement.display_position,
          instructions: @requirement.instructions_for,
          upload_rules:
        }
      end

      def upload_rules
        {
          minimum_files: @requirement.minimum_files,
          maximum_files: @requirement.maximum_files,
          combined_pdf_allowed: @requirement.combined_pdf_allowed,
          allowed_side_codes: @requirement.allowed_side_codes,
          accepted_content_types: @requirement.accepted_content_types,
          maximum_file_size: @requirement.maximum_file_size
        }
      end

      def current_status
        return 'missing' if @document.blank?

        @document.api_status
      end

      def replacement_allowed?
        return true if @document.blank?

        @document.replacement_allowed?
      end

      def serialized_document
        return if @document.blank?

        {
          id: @document.public_id,
          uploaded_at: @document.uploaded_at.utc.iso8601,
          files: @document.files.map { |file| CandidateDocumentFileSerializer.new(file).as_json }
        }.merge(legacy_file_metadata).merge(pcc_metadata).merge(review_metadata)
      end

      # Deprecated single-file fields (the representative file), kept until
      # every client reads `files`.
      def legacy_file_metadata
        primary_file = @document.primary_file
        { file_name: primary_file.original_filename, content_type: primary_file.content_type,
          file_size: primary_file.byte_size }
      end

      # Omitted (not merged as `nil`) until the document has actually been
      # reviewed -- matches the admin serializer's identical `.compact`
      # treatment of the same underlying `verified_at`/`rejection_reason`
      # columns, so the candidate sees review state the same way staff do.
      def review_metadata
        {
          reviewed_at: @document.verified_at&.utc&.iso8601,
          rejection_reason: @document.rejection_reason
        }.compact
      end

      def pcc_metadata
        return {} unless @document.police_character?

        {
          issued_on: @document.issued_on.iso8601,
          expires_on: @document.expires_on.iso8601,
          compliance_status: @document.compliance_status
        }
      end
    end
  end
end

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
          status: current_status,
          replacement_allowed: replacement_allowed?,
          document: serialized_document
        )
      end

      private

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
          file_name: @document.original_filename,
          content_type: @document.content_type,
          file_size: @document.byte_size,
          uploaded_at: @document.uploaded_at.utc.iso8601
        }.merge(pcc_metadata).merge(rejection_metadata)
      end

      def pcc_metadata
        return {} unless @document.police_character?

        {
          issued_on: @document.issued_on.iso8601,
          expires_on: @document.expires_on.iso8601,
          compliance_status: @document.compliance_status
        }
      end

      # Omitted (not merged as `nil`) for anything but a rejected document --
      # matches Admin::CandidateDocumentSerializer's identical `.compact`
      # treatment of this same column, so the candidate can see *that* a
      # document was rejected the same way staff already can.
      def rejection_metadata
        { rejection_reason: @document.rejection_reason }.compact
      end
    end
  end
end

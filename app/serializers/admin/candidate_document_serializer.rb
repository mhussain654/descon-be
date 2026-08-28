# frozen_string_literal: true

module Admin
  class CandidateDocumentSerializer
    def initialize(submission_item)
      @submission_item = submission_item
    end

    def as_json(*)
      {
        id: document.public_id,
        requirement_code: @submission_item.requirement_code,
        required: @submission_item.required,
        name: document.document_type.name_for
      }.compact
        .merge(file_metadata)
        .merge(review_metadata)
    end

    private

    def document
      @document ||= @submission_item.candidate_document
    end

    def file_metadata
      {
        file_name: document.original_filename,
        content_type: document.content_type,
        file_size: document.byte_size,
        uploaded_at: document.uploaded_at.utc.iso8601,
        status: document.api_status
      }.merge(pcc_metadata)
    end

    def review_metadata
      {
        verified_at: document.verified_at&.utc&.iso8601,
        rejection_reason: document.rejection_reason,
        reviewer_id: document.verified_by&.public_id
      }.compact
    end

    def pcc_metadata
      return {} unless document.police_character?

      {
        issued_on: document.issued_on.iso8601,
        expires_on: document.expires_on.iso8601,
        compliance_status: document.compliance_status
      }
    end
  end
end

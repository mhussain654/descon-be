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
        .merge(ocr_date_metadata)
    end

    def review_metadata
      {
        verified_at: document.verified_at&.utc&.iso8601,
        rejection_reason: document.rejection_reason,
        reviewer: serialized_reviewer
      }.compact
    end

    # No display name exists on User -- role is the only safe, non-personal
    # identifier the backend has to give (the frontend translates it into a
    # localized label; never a raw id or an invented name).
    def serialized_reviewer
      reviewer = document.verified_by
      return if reviewer.blank?

      { id: reviewer.public_id, role: reviewer.role }
    end

    def pcc_metadata
      return {} unless document.police_character?

      {
        issued_on: document.issued_on.iso8601,
        expires_on: document.expires_on.iso8601,
        compliance_status: document.compliance_status
      }
    end

    # HR-confirmed dates for an OCR-supported document type (MPS-404).
    # Unlike PCC these are optional (only present once HR has verified with
    # a confirmed date) and carry no compliance_status -- passport/CNIC
    # expiry compliance isn't a tracked concept the way PCC's is.
    def ocr_date_metadata
      return {} unless document.document_type.supports_ocr_extraction?

      { issued_on: document.issued_on&.iso8601, expires_on: document.expires_on&.iso8601 }.compact
    end
  end
end

# frozen_string_literal: true

module Admin
  # Exposes the latest OCR extraction attempt for a candidate document
  # (MPS-404) to the HR review UI: normalized dates, confidence, status,
  # and (only when failed) the error message -- never the raw Textract
  # response beyond what CandidateDocumentSerializer/DocumentExtraction
  # already retain (field type/value/confidence only, no document text
  # dump or block/geometry data).
  class DocumentExtractionSerializer
    def initialize(extraction)
      @extraction = extraction
    end

    def as_json(*)
      return { status: 'not_started' } if @extraction.blank?

      {
        status: @extraction.status,
        issued_on: @extraction.extracted_issued_on&.iso8601,
        expires_on: @extraction.extracted_expires_on&.iso8601,
        confidence_issued_on: @extraction.confidence_issued_on,
        confidence_expires_on: @extraction.confidence_expires_on,
        error_message: @extraction.failed? ? @extraction.error_message : nil,
        extracted_at: @extraction.extracted_at&.utc&.iso8601
      }.compact
    end
  end
end

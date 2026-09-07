# frozen_string_literal: true

module Candidates
  module Documents
    # Runs OCR extraction (MPS-404) for a just-uploaded passport/CNIC
    # front/back/next-of-kin-CNIC document. Idempotent: the partial unique
    # index on document_extractions (candidate_document_id where status is
    # pending/succeeded) means a duplicate job run for the same document
    # simply finds no row to create and returns -- a fresh attempt is still
    # allowed after a prior one failed. Distinguishes retryable (throttling,
    # timeout) from permanent (unsupported document, no identity document
    # detected, OCR not configured) failures; either way, HR can always
    # enter dates manually through the verify action regardless of this
    # job's outcome.
    class ExtractDatesJob < ApplicationJob
      queue_as :default

      retry_on DocumentOcr::TransientError, wait: :polynomially_longer, attempts: 3

      def perform(candidate_document_id)
        document = CandidateDocument.find(candidate_document_id)
        extraction = start_extraction(document)
        return if extraction.blank?

        run_extraction(document, extraction)
      end

      private

      def start_extraction(document)
        document.document_extractions.create!(provider: DocumentOcr::TextractAdapter::PROVIDER_NAME, status: 'pending')
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def run_extraction(document, extraction)
        result = DocumentOcr::TextractAdapter.new.extract(bytes: document.file.download)
        extraction.update!(success_attributes(result))
      rescue DocumentOcr::TransientError => e
        extraction.update!(failure_attributes(e))
        raise
      rescue DocumentOcr::PermanentError => e
        extraction.update!(failure_attributes(e))
      end

      def success_attributes(result)
        {
          status: 'succeeded',
          extracted_issued_on: result[:issued_on],
          extracted_expires_on: result[:expires_on],
          confidence_issued_on: result[:confidence_issued_on],
          confidence_expires_on: result[:confidence_expires_on],
          raw_response: { 'fields' => result[:raw_fields] },
          extracted_at: Time.current
        }
      end

      def failure_attributes(error)
        { status: 'failed', error_message: error.message, extracted_at: Time.current }
      end
    end
  end
end

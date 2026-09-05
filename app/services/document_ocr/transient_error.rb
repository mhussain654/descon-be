# frozen_string_literal: true

module DocumentOcr
  # A retryable OCR failure (throttling, timeout, transient provider/network
  # error) -- Candidates::Documents::ExtractDatesJob retries on this.
  class TransientError < StandardError; end
end

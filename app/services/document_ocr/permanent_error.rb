# frozen_string_literal: true

module DocumentOcr
  # A non-retryable OCR failure (malformed/unsupported document, missing
  # provider configuration, no identity document detected) --
  # Candidates::Documents::ExtractDatesJob records this as a failed
  # extraction without retrying. HR can always enter dates manually
  # regardless -- this never blocks document review.
  class PermanentError < StandardError; end
end

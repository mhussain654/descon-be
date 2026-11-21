# frozen_string_literal: true

module DocumentOcr
  # Reads the issue and expiry dates from one uploaded document, which may be
  # several files (CNIC front and back as two images) and/or a multi-page PDF.
  # Tries each file in the order given and, for PDFs, each of the first pages
  # (see PdfPageSplitter), stopping as soon as both dates are known, and spends
  # at most MAX_ATTEMPTS provider calls. Dates found on different pages are
  # merged. Files are only downloaded as far as they are needed.
  #
  # Usage: DocumentOcr::DateExtractor.call(sources:) where `sources` is an
  # Enumerable (ideally lazy) of file bytes, most representative file first.
  # Raises PermanentError when no date could be read anywhere (a NoDatesError
  # carrying the best IdentityMarkers result when the pages were read);
  # TransientError (retryable provider trouble) is not swallowed. The result's
  # `identity` is the best IdentityMarkers result over the pages read.
  class DateExtractor < ApplicationService
    MAX_ATTEMPTS = 3
    DATE_KEYS = %i[issued_on expires_on].freeze
    NO_DATES_MESSAGE = 'Textract found no issue or expiry date in the uploaded document'

    def initialize(sources:, adapter: TextractAdapter.new)
      @sources = sources
      @adapter = adapter
    end

    def call
      result = {}
      pages.each do |page|
        found = attempt(page)
        result = merge(result, found) if found
        break if complete?(result)
      end
      return result.merge(identity: @identity) if DATE_KEYS.any? { |key| result[key] }

      raise no_dates_error
    end

    private

    # A page that cannot be read is skipped (the next page or file may be
    # readable); the last such error is raised only if nothing is found at all.
    def attempt(page)
      found = @adapter.extract(bytes: page)
      @identity = IdentityMarkers.strongest(@identity, found[:identity])
      found
    rescue PermanentError => e
      @identity = IdentityMarkers.strongest(@identity, e.identity) if e.is_a?(NoDatesError)
      @last_error = e
      nil
    end

    # What was learnt of the pages is kept, even when the last page failed otherwise.
    def no_dates_error
      return NoDatesError.new(NO_DATES_MESSAGE, identity: @identity) if @identity
      return @last_error if @last_error

      NoDatesError.new(NO_DATES_MESSAGE)
    end

    def pages
      @sources.lazy.flat_map { |bytes| PdfPageSplitter.call(bytes:) }.take(MAX_ATTEMPTS)
    end

    def merge(current, found)
      DATE_KEYS.each_with_object(current.dup) do |key, merged|
        next if merged[key]

        merged[key] = found[key]
        merged[:"confidence_#{key}"] = found[:"confidence_#{key}"]
      end
    end

    def complete?(result) = DATE_KEYS.all? { |key| result[key] }
  end
end

# frozen_string_literal: true

module DocumentOcr
  # Says from a page's OCR text whether it looks like a Pakistani CNIC or
  # passport, without needing its dates: the dates can fail on glare or an odd
  # layout while the printed wording is still read.
  #
  # - identity_document: at least one marker found (the country or card name,
  #   "PASSPORT", a CNIC number like 12345-1234567-1, or a passport's
  #   machine-readable line);
  # - other_text: readable text, but none of the markers (another document);
  # - no_text: next to no text (a selfie, a random photo, or too blurry to read).
  #
  # Pure: looks at the text and keeps none of it.
  class IdentityMarkers < ApplicationService
    RESULTS = %w[identity_document other_text no_text].freeze
    # Fewer readable lines than this is no document at all.
    MIN_TEXT_LINES = 3
    MARKERS = [
      /ISLAMIC\s*REPUBLIC\s*OF\s*PAKISTAN/,
      /NATIONAL\s*IDENTITY\s*CARD/,
      /IDENTITY\s*(?:CARD|NUMBER)/,
      /PASSPORT/,
      /(?<!\d)\d{5}[-\s]?\d{7}[-\s]?\d(?!\d)/,
      /\AP<PAK/,
      /\A[A-Z0-9<]{30,44}\z/
    ].freeze

    # `lines`: the page's text lines (strings).
    def initialize(lines:)
      @lines = lines.map { |line| line.to_s.upcase.strip }
    end

    def call
      return 'identity_document' if marker_found?
      return 'no_text' if readable_lines < MIN_TEXT_LINES

      'other_text'
    end

    # Ranks two results, so a document's best page decides it.
    def self.strongest(*results) = results.compact.min_by { |result| RESULTS.index(result) }

    private

    def marker_found?
      @lines.any? { |line| MARKERS.any? { |marker| line.match?(marker) && mrz_ok?(marker, line) } }
    end

    # The bare machine-readable-line pattern must also carry the `<<` fillers.
    def mrz_ok?(marker, line) = marker != MARKERS.last || line.include?('<<')

    def readable_lines = @lines.count { |line| line.scan(/[A-Z0-9]/).size >= 3 }
  end
end

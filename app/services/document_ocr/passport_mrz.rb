# frozen_string_literal: true

module DocumentOcr
  # Reads the date of birth and the expiry date from a passport's machine
  # readable zone (MRZ) -- the two 44-character lines of letters, digits and
  # `<` at the foot of the data page (ICAO 9303 TD3). Each date there carries a
  # check digit, so a date read from it is trusted over a free-text answer.
  # The MRZ has no issue date. Only these two dates are returned; the rest of
  # the line (name, passport number) is never kept.
  #
  # Usage: DocumentOcr::PassportMrz.call(lines: [['P<PAK...', 99.1], ['AB1234567...', 98.7]])
  # Returns { birth_date:, expires_on:, confidence: } or nil when no valid MRZ line is found.
  class PassportMrz < ApplicationService
    LINE_LENGTH = 44
    # Passport number (9) + check, nationality (3), birth date (6) + check, sex, expiry (6) + check.
    LINE_FORMAT = /
      \A[A-Z0-9<]{9}[0-9<][A-Z<]{3}
      (?<birth>\d{6})(?<birth_check>\d)[MFX<](?<expiry>\d{6})(?<expiry_check>\d)
    /x
    WEIGHTS = [7, 3, 1].freeze

    # `lines` are the page's text lines with their confidence: [[text, confidence], ...].
    def initialize(lines:)
      @lines = lines
    end

    def call
      @lines.each do |text, confidence|
        dates = dates_from(text.to_s.delete(' ').upcase)
        return dates.merge(confidence:) if dates
      end
      nil
    end

    private

    def dates_from(line)
      return unless line.length == LINE_LENGTH

      match = LINE_FORMAT.match(line)
      return unless match && valid?(match[:birth], match[:birth_check]) && valid?(match[:expiry], match[:expiry_check])

      birth_date = parse(match[:birth], century_for_birth(match[:birth]))
      expires_on = parse(match[:expiry], 2000)
      { birth_date:, expires_on: } if birth_date && expires_on
    end

    def valid?(digits, check) = checksum(digits) == check.to_i

    def checksum(digits)
      digits.chars.each_with_index.sum { |char, index| char.to_i * WEIGHTS[index % 3] } % 10
    end

    # A two-digit birth year later than this year belongs to the previous century.
    def century_for_birth(yymmdd) = yymmdd[0, 2].to_i > (Date.current.year % 100) ? 1900 : 2000

    def parse(yymmdd, century)
      Date.new(century + yymmdd[0, 2].to_i, yymmdd[2, 2].to_i, yymmdd[4, 2].to_i)
    rescue Date::Error
      nil
    end
  end
end

# frozen_string_literal: true

module DocumentOcr
  # Chooses the issue and expiry dates from what Textract read on one page.
  # A passport data page prints the date of birth next to the issue and
  # expiry dates, and Textract sometimes answers an issue or expiry query with
  # the birth date, so:
  # - a passport's MRZ gives the trusted expiry (and birth) date (PassportMrz);
  # - an answer that is the birth date, an issue date in the future, or one not
  #   before the expiry is dropped;
  # - a passport whose issue answer was dropped takes the printed date that is
  #   neither the birth date nor in the future and comes before the expiry.
  # A date that cannot be chosen is left nil for staff to enter.
  #
  # `answers`: { issue:, expiry:, birth: } each [text, confidence] or nil.
  # `lines`: the page's text lines as [[text, confidence], ...] (never kept).
  # Returns { issue: [date, confidence] or nil, expiry: [date, confidence] or nil }.
  class DatePicker < ApplicationService
    def initialize(answers:, lines:)
      @answers = answers
      @lines = lines
      @mrz = PassportMrz.call(lines:)
    end

    def call
      expiry = pick_expiry
      { issue: pick_issue(expiry&.first), expiry: }
    end

    private

    def birth_date = @mrz&.dig(:birth_date) || answered_date(:birth)

    def pick_expiry
      return [@mrz[:expires_on], @mrz[:confidence]] if @mrz

      date = answered_date(:expiry)
      [date, @answers.dig(:expiry, 1)] if date && date != birth_date
    end

    def pick_issue(expires_on)
      date = answered_date(:issue)
      return [date, @answers.dig(:issue, 1)] if plausible_issue?(date, expires_on)

      issue_from_printed_dates(expires_on) if @mrz
    end

    def plausible_issue?(date, expires_on)
      date.present? && date != birth_date && date <= Date.current && (expires_on.nil? || date < expires_on)
    end

    def issue_from_printed_dates(expires_on)
      @lines.filter_map { |text, confidence| [PrintedDate.parse(text), confidence] }
            .select { |date, _| plausible_issue?(date, expires_on) }
            .max_by(&:first)
    end

    def answered_date(key) = PrintedDate.parse(@answers.dig(key, 0))
  end
end

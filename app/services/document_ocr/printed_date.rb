# frozen_string_literal: true

module DocumentOcr
  # Parses a date as printed on a CNIC (06.12.2021) or passport (06 DEC 2021); nil for anything else.
  module PrintedDate
    FORMATS = ['%d.%m.%Y', '%d/%m/%Y', '%d-%m-%Y', '%d %b %Y', '%d %B %Y', '%Y-%m-%d'].freeze

    module_function

    def parse(raw)
      text = raw.to_s.strip
      return unless text.match?(/\d{4}/)

      FORMATS.each do |format|
        return Date.strptime(text, format)
      rescue ArgumentError
        next
      end
      nil
    end
  end
end

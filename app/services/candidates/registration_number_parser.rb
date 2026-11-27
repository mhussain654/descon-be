# frozen_string_literal: true

module Candidates
  # Reads a registration number typed by staff or taken from a CSV: blank means none, otherwise a whole number above
  # zero of up to 15 digits (spaces around it are ignored; "00042" is 42).
  class RegistrationNumberParser
    FORMAT = /\A\d{1,15}\z/
    Result = Data.define(:value, :valid) do
      def valid? = valid
    end

    # The number a staff search box holds, when it is one (to match a registration number).
    def self.search_number(value) = value.to_s.strip.match?(FORMAT) ? value.to_s.strip.to_i : nil

    def self.call(raw)
      text = raw.to_s.strip
      return Result.new(value: nil, valid: true) if text.empty?
      return Result.new(value: nil, valid: false) unless text.match?(FORMAT) && text.to_i.positive?

      Result.new(value: text.to_i, valid: true)
    end
  end
end

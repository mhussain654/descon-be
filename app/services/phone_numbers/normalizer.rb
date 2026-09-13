# frozen_string_literal: true

module PhoneNumbers
  # Strips whitespace and keeps only digits (plus a leading '+' if present) --
  # the same normalization `Candidate#normalize_mobile_number` applies before
  # storage, extracted here so a caller-ID number can be compared against
  # `Candidate#mobile_number` on equal terms without duplicating the rule
  # (AGENTS.md: "Normalize and validate... phone input at the boundary").
  module Normalizer
    def self.call(raw_number)
      raw_value = raw_number.to_s.strip
      digits = raw_value.gsub(/\D/, '')
      return '' if digits.blank?

      raw_value.start_with?('+') ? "+#{digits}" : digits
    end
  end
end

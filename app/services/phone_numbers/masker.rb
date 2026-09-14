# frozen_string_literal: true

module PhoneNumbers
  # Masks a phone number for display/logging -- keeps the leading country/
  # area-code digits and the trailing two digits, stars out the rest (e.g.
  # '+923001234512' -> '+92300*****12'). Shared by Communication#recipient_masked
  # and CandidateAiCall#caller_number_masked rather than each channel
  # reimplementing its own masking rule.
  module Masker
    VISIBLE_PREFIX_LENGTH = 6
    VISIBLE_SUFFIX_LENGTH = 2

    def self.call(number)
      digits = number.to_s
      minimum_length = VISIBLE_PREFIX_LENGTH + VISIBLE_SUFFIX_LENGTH
      return digits if digits.length <= minimum_length

      prefix = digits[0, VISIBLE_PREFIX_LENGTH]
      suffix = digits[-VISIBLE_SUFFIX_LENGTH, VISIBLE_SUFFIX_LENGTH]
      "#{prefix}#{'*' * (digits.length - minimum_length)}#{suffix}"
    end
  end
end

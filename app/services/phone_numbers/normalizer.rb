# frozen_string_literal: true

module PhoneNumbers
  # Normalizes any candidate-submitted phone number into one canonical
  # E.164 representation, so equality lookups that depend on it (inbound
  # AI-call caller-ID matching in AiCalls::HandleConversationInitiationService
  # and AiCalls::Tools::VerifyCallerIdentity, and the outbound `to_number`
  # sent to ElevenLabs/Twilio) never depend on which of several equivalent
  # local/international spellings a candidate happened to submit -- a
  # previous version preserved whichever prefix style was already present
  # (e.g. '03001234567' and '+923001234567' normalized to themselves,
  # unchanged, even though they're the same number).
  #
  # Assumes Pakistan (+92) as the sole country code this platform serves
  # today, matching every other Pakistan-specific format already enforced
  # in this codebase (Candidate::CNIC_FORMAT, the mobile-number length
  # bounds). Extending to other countries would need an explicit country
  # code parameter, not a guess from the raw input.
  module Normalizer
    COUNTRY_CODE = '92'
    LOCAL_TRUNK_PREFIX = '0'
    NATIONAL_SIGNIFICANT_DIGITS_LENGTH = 10
    FULL_DIGITS_LENGTH = COUNTRY_CODE.length + NATIONAL_SIGNIFICANT_DIGITS_LENGTH

    def self.call(raw_number)
      raw_value = raw_number.to_s.strip
      digits = raw_value.gsub(/\D/, '')
      return '' if digits.blank?

      "+#{country_coded_digits(raw_value:, digits:)}"
    end

    def self.country_coded_digits(raw_value:, digits:)
      return digits if raw_value.start_with?('+')
      return digits if digits.start_with?(COUNTRY_CODE) && digits.length == FULL_DIGITS_LENGTH
      return "#{COUNTRY_CODE}#{digits[1..]}" if digits.start_with?(LOCAL_TRUNK_PREFIX)

      "#{COUNTRY_CODE}#{digits}"
    end
    private_class_method :country_coded_digits
  end
end

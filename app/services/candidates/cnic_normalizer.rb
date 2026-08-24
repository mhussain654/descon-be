# frozen_string_literal: true

module Candidates
  # Normalizes CNIC input to the canonical NNNNN-NNNNNNN-N storage/lookup
  # format. Shared by Candidate's own before_validation normalization and by
  # CandidateAuthentication::Otp's request/verify lookups, so a candidate is
  # found by CNIC regardless of whether the caller's input included dashes
  # (AGENTS.md: "Normalize and validate CNIC and phone input at the
  # boundary").
  module CnicNormalizer
    def self.call(raw_cnic)
      normalized_input = raw_cnic.to_s.strip
      return normalized_input unless normalized_input.match?(/\A(?:\d{13}|\d{5}-\d{7}-\d)\z/)

      digits = normalized_input.delete('-')
      "#{digits[0, 5]}-#{digits[5, 7]}-#{digits[12]}"
    end
  end
end

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
      digits = raw_cnic.to_s.gsub(/\D/, '')
      return raw_cnic.to_s if digits.length != 13

      "#{digits[0, 5]}-#{digits[5, 7]}-#{digits[12]}"
    end
  end
end

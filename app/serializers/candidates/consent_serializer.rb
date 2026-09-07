# frozen_string_literal: true

module Candidates
  # Serializes a candidate's consent status against the currently-required policy version.
  class ConsentSerializer
    def initialize(candidate)
      @candidate = candidate
    end

    def as_json(*)
      {
        current_policy_version: CandidateConsent::CURRENT_POLICY_VERSION,
        accepted: current_consent.present?,
        accepted_at: current_consent&.accepted_at&.iso8601
      }
    end

    private

    def current_consent
      return @current_consent if defined?(@current_consent)

      @current_consent = @candidate.candidate_consents.find_by(
        policy_version: CandidateConsent::CURRENT_POLICY_VERSION
      )
    end
  end
end

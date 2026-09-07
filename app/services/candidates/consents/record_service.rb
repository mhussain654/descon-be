# frozen_string_literal: true

module Candidates
  module Consents
    # Records a candidate's acceptance of the current policy version, idempotently -- calling
    # this again for a candidate who already accepted the current version just returns the
    # existing (immutable) row rather than raising a uniqueness error.
    class RecordService < ApplicationService
      def initialize(candidate:, ip_address:)
        @candidate = candidate
        @ip_address = ip_address
      end

      def call
        existing_consent_for_current_policy || create_consent!
      end

      private

      attr_reader :candidate, :ip_address

      def existing_consent_for_current_policy
        candidate.candidate_consents.find_by(policy_version: CandidateConsent::CURRENT_POLICY_VERSION)
      end

      def create_consent!
        candidate.candidate_consents.create!(
          policy_version: CandidateConsent::CURRENT_POLICY_VERSION,
          accepted_at: Time.current,
          ip_address:
        )
      end
    end
  end
end

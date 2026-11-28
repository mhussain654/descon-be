# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # One Candidates-tab row (a candidate loaded by CandidateIndexQuery with
    # its OTP and sign-in aggregates). The CNIC is masked.
    class CandidateRowSerializer
      COPIED_ATTRIBUTES = %w[
        full_name registration_number active otp_count last_otp_at login_count last_login_at last_seen_at
      ].freeze

      def initialize(row)
        @row = row
      end

      def as_json(*)
        {
          id: @row.public_id,
          masked_cnic: ::Candidates::CnicMasker.call(@row.cnic),
          store_review_account: ::StoreReview::Account.candidate?(@row)
        }.merge(@row.attributes.slice(*COPIED_ATTRIBUTES).symbolize_keys)
      end
    end
  end
end

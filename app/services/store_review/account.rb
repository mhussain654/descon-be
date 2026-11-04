# frozen_string_literal: true

module StoreReview
  # The one demo candidate Google Play and App Store reviewers sign in as.
  # They can't receive the sign-in SMS, so this account's code is fixed and no
  # SMS is ever sent for it (CandidateAuthentication::Otp::RequestService).
  # Verification is unchanged: the code is still single-use, expires and
  # locks after too many wrong attempts. The account also never advances on
  # its own (CandidateWorkflows::AutomaticTransitionService), so it stays at
  # Enrolled and can't reach the fee step.
  #
  # Off unless both values are set in the encrypted credentials:
  #   store_review:
  #     production:
  #       cnic: 12345-1234567-1
  #       otp_code: '123456'
  module Account
    module_function

    def enabled? = cnic.present? && otp_code.present?

    def cnic
      value = Candidates::CnicNormalizer.call(setting(:cnic))
      value if value.match?(Candidate::CNIC_FORMAT)
    end

    def otp_code
      value = setting(:otp_code)
      value if value.match?(/\A\d{#{CandidateOtpChallenge::CODE_LENGTH}}\z/o)
    end

    def cnic?(value) = enabled? && Candidates::CnicNormalizer.call(value) == cnic

    def candidate?(candidate) = candidate.present? && cnic?(candidate.cnic)

    # The reviewer's code is fixed rather than random, so every sign-in with
    # it is audited. Does nothing for any other candidate.
    def record_sign_in!(candidate:, candidate_session:)
      return unless candidate?(candidate)

      AuditEvent.create!(
        candidate:, entity_type: 'CandidateSession', entity_id: candidate_session.id,
        action_code: 'store_review_signed_in', metadata: { candidate_public_id: candidate.public_id },
        occurred_at: Time.current
      )
    end

    def setting(key)
      Rails.application.credentials.dig(:store_review, Rails.env.to_sym, key).to_s.strip
    end
  end
end

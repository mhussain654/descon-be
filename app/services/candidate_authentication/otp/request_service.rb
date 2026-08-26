# frozen_string_literal: true

module CandidateAuthentication
  module Otp
    # Always returns the same generic result shape regardless of whether the
    # CNIC resolves to a real candidate -- callers must not be able to tell
    # unknown-CNIC, missing/invalid mobile, and success apart (ticket:
    # "Responses do not reveal whether a CNIC exists or whether its stored
    # mobile is missing/invalid"). A real candidate's mobile is always
    # present (a NOT NULL, format-checked column -- see Candidate); what
    # this class treats as "invalid mobile" is an SMS-provider-level
    # delivery failure for an otherwise well-formed number, which never
    # changes the response either.
    #
    # An unknown CNIC also gets a real challenge row and a real call through
    # the SMS adapter (see #deliver_decoy) -- both at the same cost as a real
    # candidate's -- so neither this endpoint's response body nor its
    # latency can be used to distinguish a known CNIC from an unknown one.
    class RequestService < ApplicationService
      LOCK_SCOPE = 'candidate_otp'

      # A well-formed-looking, never-real number used only so a decoy
      # delivery attempt exercises the same SMS-adapter code path, at the
      # same cost, as a real candidate's delivery. Mirrors VerifyService's
      # DUMMY_DIGEST, which gives the same guarantee to /verify.
      DECOY_MOBILE_NUMBER = '+920000000001'

      def initialize(cnic:, ip_address:)
        @cnic = Candidates::CnicNormalizer.call(cnic)
        @ip_address = ip_address
      end

      def call
        raise ValidationError.new(field: 'cnic', message: I18n.t('api.errors.cnic_invalid')) unless valid_cnic_format?

        request_challenge

        {
          expires_in_seconds: CandidateOtpChallenge::EXPIRY_WINDOW.to_i,
          resend_after_seconds: CandidateOtpChallenge::RESEND_COOLDOWN.to_i
        }
      end

      private

      def valid_cnic_format?
        @cnic.match?(Candidate::CNIC_FORMAT)
      end

      # Always creates a challenge row and always calls through the SMS
      # adapter, for a real candidate or a decoy alike, so an unknown CNIC is
      # handled by the identical code path as a real one (see
      # CandidateOtpChallenge#belongs_to :candidate, optional: true). This is
      # what lets VerifyService return otp_expired/otp_max_attempts
      # symmetrically for both, instead of only ever for a real candidate.
      def request_challenge
        challenge_payload = create_challenge_payload
        return unless challenge_payload

        deliver_challenge(challenge_payload)
      end

      def within_resend_cooldown?
        latest = latest_challenge_for_cnic
        latest.present? && latest.created_at > CandidateOtpChallenge::RESEND_COOLDOWN.ago
      end

      def latest_challenge_for_cnic
        CandidateOtpChallenge.where(cnic: @cnic).order(created_at: :desc).first
      end

      def deliver(candidate:, code:, locale:)
        body = sms_body(code:, locale:)
        result = Sms::SendMessage.call(to: candidate.mobile_number, body:)
        return if result.success?

        Rails.logger.warn(
          { event: 'otp_delivery_failed', candidate_id: candidate.id, error_code: result.error_code }.to_json
        )
      rescue StandardError => e
        # A delivery failure (expected or not) must never change this
        # service's return value or raise -- the challenge is already
        # created and verifiable regardless of whether the SMS itself
        # arrived.
        Rails.logger.error(
          { event: 'otp_delivery_error', candidate_id: candidate.id, error_class: e.class.name }.to_json
        )
      end

      # Result and any error are both discarded -- this call exists purely
      # to pay the same latency as #deliver, never to reach a real recipient.
      def deliver_decoy(code:, locale:)
        Sms::SendMessage.call(to: DECOY_MOBILE_NUMBER, body: sms_body(code:, locale:))
      rescue StandardError
        nil
      end

      def create_challenge_payload
        challenge_payload = nil

        ActiveRecord::Base.transaction do
          lock_cnic!
          next if within_resend_cooldown?

          candidate = Candidate.active.find_by(cnic: @cnic)
          challenge_payload = CandidateOtpChallenge.generate_for(candidate:, cnic: @cnic, requested_ip: @ip_address)
          challenge_payload[:candidate] = candidate
        end

        challenge_payload
      end

      def deliver_challenge(challenge_payload)
        candidate = challenge_payload.fetch(:candidate)
        code = challenge_payload.fetch(:code)
        locale = I18n.locale.to_s

        candidate ? deliver(candidate:, code:, locale:) : deliver_decoy(code:, locale:)
      end

      def lock_cnic!
        Database::AdvisoryTransactionLock.call(scope: LOCK_SCOPE, key: @cnic)
      end

      def sms_body(code:, locale:)
        I18n.t(
          'api.authentication.otp_sms_body',
          code:,
          expiry_minutes: (CandidateOtpChallenge::EXPIRY_WINDOW / 1.minute).round,
          locale:
        )
      end
    end
  end
end

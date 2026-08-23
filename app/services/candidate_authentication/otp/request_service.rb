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
    class RequestService < ApplicationService
      def initialize(cnic:, ip_address:)
        @cnic = Candidates::CnicNormalizer.call(cnic)
        @ip_address = ip_address
      end

      def call
        raise ValidationError.new(field: 'cnic', message: I18n.t('api.errors.cnic_invalid')) unless valid_cnic_format?

        candidate = Candidate.find_by(cnic: @cnic)
        request_challenge(candidate) if candidate

        {
          expires_in_seconds: CandidateOtpChallenge::EXPIRY_WINDOW.to_i,
          resend_after_seconds: CandidateOtpChallenge::RESEND_COOLDOWN.to_i
        }
      end

      private

      def valid_cnic_format?
        @cnic.match?(Candidate::CNIC_FORMAT)
      end

      def request_challenge(candidate)
        return if within_resend_cooldown?(candidate)

        result = CandidateOtpChallenge.generate_for(candidate:, requested_ip: @ip_address)
        deliver(candidate:, code: result.fetch(:code))
      end

      def within_resend_cooldown?(candidate)
        latest = latest_challenge_for(candidate)
        latest.present? && latest.created_at > CandidateOtpChallenge::RESEND_COOLDOWN.ago
      end

      def latest_challenge_for(candidate)
        candidate.candidate_otp_challenges.order(created_at: :desc).first
      end

      def deliver(candidate:, code:)
        result = Sms::SendMessage.call(to: candidate.mobile_number, body: sms_body(candidate:, code:))
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

      def sms_body(candidate:, code:)
        I18n.t(
          'api.authentication.otp_sms_body',
          code:,
          expiry_minutes: (CandidateOtpChallenge::EXPIRY_WINDOW / 1.minute).round,
          locale: candidate.preferred_locale
        )
      end
    end
  end
end

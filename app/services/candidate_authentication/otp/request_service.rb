# frozen_string_literal: true

module CandidateAuthentication
  module Otp
    # Client-approved, deliberate exception to the usual "never disclose
    # whether an identifier exists" rule: a CNIC that matches no active
    # candidate raises CandidateCnicNotFoundError (404) immediately, rather
    # than the generic, non-enumerating response this endpoint used to
    # return for every CNIC alike. See CandidateCnicNotFoundError's own doc
    # comment and AGENTS.md's "Security requirements" section for why --
    # this app is reachable only by the client's own already-registered
    # candidates, not the public, and the client asked for this specifically
    # so a candidate who mistyped their own CNIC can tell.
    #
    # A real candidate's mobile is always present (a NOT NULL, format-checked
    # column -- see Candidate); what this class treats as "invalid mobile" is
    # an SMS-provider-level delivery failure for an otherwise well-formed
    # number, which never changes the response (delivery failures are still
    # never disclosed -- only non-existence is, per the client's decision).
    class RequestService < ApplicationService
      LOCK_SCOPE = 'candidate_otp'

      def initialize(cnic:, ip_address:)
        @cnic = Candidates::CnicNormalizer.call(cnic)
        @ip_address = ip_address
      end

      def call
        raise ValidationError.new(field: 'cnic', message: I18n.t('api.errors.cnic_invalid')) unless valid_cnic_format?

        request_verification_challenge

        {
          expires_in_seconds: CandidateOtpChallenge::EXPIRY_WINDOW.to_i,
          resend_after_seconds: CandidateOtpChallenge::RESEND_COOLDOWN.to_i
        }
      end

      private

      def valid_cnic_format?
        @cnic.match?(Candidate::CNIC_FORMAT)
      end

      def request_verification_challenge
        challenge_payload = build_verification_challenge_payload
        return unless challenge_payload

        deliver(candidate: challenge_payload.fetch(:candidate), code: challenge_payload.fetch(:code),
                locale: I18n.locale.to_s)
      end

      def within_resend_cooldown?
        latest = latest_challenge_for_cnic
        latest.present? && latest.created_at > CandidateOtpChallenge::RESEND_COOLDOWN.ago
      end

      def latest_challenge_for_cnic
        CandidateOtpChallenge.where(cnic: @cnic).order(created_at: :desc).first
      end

      def deliver(candidate:, code:, locale:)
        result = send_sms(to: candidate.mobile_number, code:, locale:)
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

      def build_verification_challenge_payload
        challenge_payload = nil

        ActiveRecord::Base.transaction do
          lock_cnic!

          candidate = Candidate.active.find_by(cnic: @cnic)
          raise CandidateCnicNotFoundError unless candidate

          next if within_resend_cooldown?

          challenge_payload = CandidateOtpChallenge.generate_for(candidate:, requested_ip: @ip_address)
          challenge_payload[:candidate] = candidate
        end

        challenge_payload
      end

      def lock_cnic!
        Database::AdvisoryTransactionLock.call(scope: LOCK_SCOPE, key: @cnic)
      end

      def send_sms(to:, code:, locale:)
        Sms::SendMessage.call(to:, body: sms_body(code:, locale:), variables: sms_variables(code:), locale:)
      end

      def sms_body(code:, locale:)
        I18n.t('api.authentication.otp_sms_body', code:, expiry_minutes:, locale:)
      end

      # Values for the vendor's approved OTP template (variables #code# and
      # #minutes#). The template text itself is English-only for now.
      def sms_variables(code:)
        { code:, minutes: expiry_minutes }
      end

      def expiry_minutes
        (CandidateOtpChallenge::EXPIRY_WINDOW / 1.minute).round
      end
    end
  end
end

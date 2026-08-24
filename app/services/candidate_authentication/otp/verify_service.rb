# frozen_string_literal: true

module CandidateAuthentication
  module Otp
    class VerifyService < ApplicationService
      # A real bcrypt comparison takes measurably longer than raising
      # immediately, which would let response timing (not just the response
      # body) leak whether a CNIC/challenge exists. Comparing against this
      # fixed dummy digest on every not-found path keeps timing consistent
      # with the real comparison in #evaluate. Computed once at class load,
      # not per-request.
      DUMMY_DIGEST = BCrypt::Password.create('0' * CandidateOtpChallenge::CODE_LENGTH).freeze
      CODE_FORMAT = /\A\d{#{CandidateOtpChallenge::CODE_LENGTH}}\z/

      def initialize(cnic:, code:, user_agent:, ip_address:)
        @cnic = Candidates::CnicNormalizer.call(cnic)
        @code = code.to_s
        @user_agent = user_agent
        @ip_address = ip_address
      end

      def call
        validate_format!

        challenge = latest_challenge_for_cnic

        unless challenge
          # Discarded on purpose -- performed only to normalize response
          # timing against the real comparison below, see DUMMY_DIGEST.
          # Reached only when this CNIC (real or unknown) has never had
          # /request called for it, so no challenge row -- decoy or real --
          # exists yet to compare against.
          BCrypt::Password.new(DUMMY_DIGEST) == @code # rubocop:disable Lint/Void
          raise OtpInvalidError
        end

        evaluate(challenge:)
      end

      private

      def validate_format!
        raise ValidationError.new(field: 'cnic', message: I18n.t('api.errors.cnic_invalid')) unless valid_cnic_format?
        return if valid_code_format?

        raise ValidationError.new(field: 'otp', message: I18n.t('api.errors.otp_format_invalid'))
      end

      def valid_cnic_format?
        @cnic.match?(Candidate::CNIC_FORMAT)
      end

      def valid_code_format?
        @code.match?(CODE_FORMAT)
      end

      def latest_challenge_for_cnic
        CandidateOtpChallenge.where(cnic: @cnic).order(created_at: :desc).first
      end

      # A decoy challenge (challenge.candidate nil) can still be consumed,
      # expired or locked exactly like a real one -- otp_expired and
      # otp_max_attempts are reachable either way, closing the
      # identity-enumeration oracle. #match? always runs (bcrypt has
      # constant cost regardless of its input) so a decoy's wrong-code path
      # costs the same as a real candidate's; only the candidate check
      # below, not the comparison itself, gates success.
      def evaluate(challenge:)
        raise OtpInvalidError if challenge.consumed?
        raise OtpExpiredError if challenge.expired?
        raise OtpMaxAttemptsError if challenge.locked?

        matched = challenge.match?(@code)

        if matched && challenge.candidate
          succeed(candidate: challenge.candidate, challenge:)
        else
          fail_attempt(challenge)
        end
      end

      def fail_attempt(challenge)
        challenge.register_failed_attempt!
        raise(challenge.locked? ? OtpMaxAttemptsError : OtpInvalidError)
      end

      def succeed(candidate:, challenge:)
        challenge.consume!
        candidate_session = candidate.candidate_sessions.create!(user_agent: @user_agent, ip_address: @ip_address)
        issue_tokens(candidate:, candidate_session:)
      end

      def issue_tokens(candidate:, candidate_session:)
        access_token = TokenIssuer.call(candidate:, candidate_session:)
        refresh_token = RefreshTokenIssuer.call(candidate_session:)

        { candidate:, candidate_session:, access_token:, refresh_token: }
      end
    end
  end
end

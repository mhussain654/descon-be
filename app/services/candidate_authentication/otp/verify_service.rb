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
        evaluate
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

      # A decoy challenge (challenge.candidate nil) can still be consumed,
      # expired or locked exactly like a real one -- otp_expired and
      # otp_max_attempts are reachable either way, closing the
      # identity-enumeration oracle. #match? always runs (bcrypt has
      # constant cost regardless of its input) so a decoy's wrong-code path
      # costs the same as a real candidate's; only the candidate check
      # below, not the comparison itself, gates success.
      def evaluate
        result, raised_error = evaluate_challenge

        raise raised_error if raised_error

        result
      end

      def evaluate_challenge
        result = nil
        raised_error = nil

        ActiveRecord::Base.transaction do
          challenge = latest_challenge_under_lock
          next if missing_challenge?(challenge) { raised_error = OtpInvalidError }

          challenge.lock!
          next if challenge_state_error_present?(challenge) { |error| raised_error = error }

          result, raised_error = handle_challenge_match(challenge)
        end

        [result, raised_error]
      end

      def latest_challenge_under_lock
        lock_cnic!
        latest_challenge_for_cnic
      end

      def missing_challenge?(challenge)
        return false if challenge

        normalize_missing_challenge_timing!
        yield
        true
      end

      def challenge_state_error_present?(challenge)
        error = challenge_state_error(challenge)
        return false unless error

        yield(error)
        true
      end

      def handle_challenge_match(challenge)
        if challenge.match?(@code) && challenge.candidate
          [succeed(candidate: challenge.candidate, challenge:), nil]
        else
          challenge.register_failed_attempt!
          [nil, failed_attempt_error(challenge)]
        end
      end

      def succeed(candidate:, challenge:)
        raise InactiveAccountError unless candidate.active_for_authentication?

        challenge.consume!
        candidate_session = candidate.candidate_sessions.create!(user_agent: @user_agent, ip_address: @ip_address)
        refresh_token = RefreshTokenIssuer.call(candidate_session:)
        access_token = TokenIssuer.call(candidate:, candidate_session:)

        { candidate:, candidate_session:, access_token:, refresh_token: }
      end

      def challenge_state_error(challenge)
        return OtpInvalidError if challenge.consumed?
        return OtpExpiredError if challenge.expired?
        return OtpMaxAttemptsError if challenge.locked?

        nil
      end

      def failed_attempt_error(challenge)
        challenge.locked? ? OtpMaxAttemptsError : OtpInvalidError
      end

      def latest_challenge_for_cnic
        CandidateOtpChallenge.where(cnic: @cnic).order(created_at: :desc).first
      end

      def lock_cnic!
        Database::AdvisoryTransactionLock.call(scope: RequestService::LOCK_SCOPE, key: @cnic)
      end

      def normalize_missing_challenge_timing!
        # Discarded on purpose -- performed only to normalize response
        # timing against the real comparison below, see DUMMY_DIGEST.
        # Reached only when this CNIC (real or unknown) has never had
        # /request called for it, so no challenge row -- decoy or real --
        # exists yet to compare against.
        _matched = BCrypt::Password.new(DUMMY_DIGEST) == @code
        nil
      end
    end
  end
end

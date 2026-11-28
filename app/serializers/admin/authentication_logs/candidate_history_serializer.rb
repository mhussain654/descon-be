# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # A candidate's recent sign-ins (one per session) and the sign-in codes
    # sent to them, newest first. Never includes a code or its digest.
    class CandidateHistorySerializer
      def initialize(sessions:, otp_challenges:)
        @sessions = sessions
        @otp_challenges = otp_challenges
      end

      def as_json(*)
        {
          sign_ins: @sessions.map { |session| sign_in(session) },
          otps: @otp_challenges.map { |challenge| otp(challenge) }
        }
      end

      private

      def sign_in(session)
        {
          signed_in_at: session.created_at,
          last_seen_at: session.last_seen_at || session.created_at,
          signed_out_at: session.revoked_at,
          ip_address: session.ip_address,
          user_agent: session.user_agent
        }
      end

      def otp(challenge)
        {
          sent_at: challenge.created_at,
          status: otp_status(challenge),
          used_at: challenge.consumed_at,
          wrong_attempts: challenge.attempts,
          ip_address: challenge.requested_ip
        }
      end

      def otp_status(challenge)
        return 'used' if challenge.consumed_at.present?
        return 'locked' if challenge.locked?
        return 'expired' if challenge.expires_at <= Time.current

        'pending'
      end
    end
  end
end

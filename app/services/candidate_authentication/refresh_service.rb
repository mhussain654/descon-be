# frozen_string_literal: true

module CandidateAuthentication
  # Exchanges a candidate refresh token for a new access/refresh pair.
  # Mirrors Authentication::RefreshService: the presented token is rotated
  # (single use), presenting an already-rotated token revokes the whole
  # session (reuse detection), and an inactive candidate cannot refresh.
  class RefreshService < ApplicationService
    def initialize(refresh_token:, user_agent:, ip_address:)
      @refresh_token = refresh_token
      @user_agent = user_agent.to_s.first(255)
      @ip_address = ip_address
    end

    def call
      token_record = CandidateRefreshToken.find_by(token_digest: digest(@refresh_token))
      raise InvalidRefreshTokenError unless token_record

      result, failure = rotate_or_fail(token_record)
      raise failure if failure

      result
    end

    private

    # Failures that must persist a side effect (revoking the session) are
    # decided inside the transaction and raised by the caller only after it
    # commits, so the revoke is not rolled back by the exception.
    def rotate_or_fail(token_record)
      CandidateRefreshToken.transaction do
        session, candidate = lock_records(token_record)
        failure = failure_for(token_record, session, candidate)
        [failure ? nil : rotate(token_record, session, candidate), failure]
      end
    end

    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token.to_s)
    end

    def lock_records(token_record)
      token_record.lock!
      session = token_record.candidate_session.lock!
      [session, session.candidate.lock!]
    end

    def failure_for(token_record, session, candidate)
      if token_record.rotated?
        session.revoke!
        return InvalidRefreshTokenError
      end

      unless candidate.active_for_authentication?
        session.revoke!
        return InactiveAccountError
      end

      return RevokedSessionError if session.revoked?

      InvalidRefreshTokenError unless token_record.active?
    end

    def rotate(token_record, session, candidate)
      replacement_token = RefreshTokenIssuer.call(candidate_session: session)
      replacement = CandidateRefreshToken.find_by!(token_digest: digest(replacement_token))
      token_record.update!(rotated_at: Time.current, replaced_by_id: replacement.id)
      session.update!(user_agent: @user_agent, ip_address: @ip_address, last_seen_at: Time.current)

      {
        candidate:,
        candidate_session: session,
        access_token: TokenIssuer.call(candidate:, candidate_session: session),
        refresh_token: replacement_token
      }
    end
  end
end

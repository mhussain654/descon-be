# frozen_string_literal: true

module Authentication
  class RefreshService < ApplicationService
    def initialize(refresh_token:, user_agent:, ip_address:, request_id:)
      @refresh_token = refresh_token
      @user_agent = user_agent
      @ip_address = ip_address
      @request_id = request_id
    end

    def call
      token_record = RefreshToken.find_by(token_digest: token_digest(@refresh_token))
      return invalid_refresh_token! unless token_record

      result = nil

      RefreshToken.transaction do
        token_record.lock!
        session = token_record.session.lock!

        if token_record.rotated?
          session.revoke!
          log_event('refresh_token_reuse_detected', user: session.user, session:)
          result = :reused_token
          next
        end

        raise RevokedSessionError if session.revoked?
        raise InvalidRefreshTokenError unless token_record.active?

        replacement_token = RefreshTokenIssuer.call(session:)
        token_record.update!(rotated_at: Time.current, replaced_by_id: refresh_token_record_for(replacement_token).id)
        session.update!(user_agent: @user_agent, ip_address: @ip_address, last_seen_at: Time.current)

        result = {
          user: session.user,
          session:,
          access_token: TokenIssuer.call(user: session.user, session:),
          refresh_token: replacement_token
        }

        log_event('refresh_succeeded', user: session.user, session:)
      end

      raise InvalidRefreshTokenError if result == :reused_token

      result
    end

    private

    def refresh_token_record_for(raw_token)
      RefreshToken.find_by!(token_digest: token_digest(raw_token))
    end

    def token_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    def invalid_refresh_token!
      log_event('refresh_failed', metadata: { reason: 'token_not_found' })
      raise InvalidRefreshTokenError
    end

    def log_event(event_code, user: nil, session: nil, metadata: {})
      EventLogger.call(
        event_code:,
        context: request_context,
        subject: { user:, session: },
        metadata:
      )
    end

    def request_context
      { request_id: @request_id, ip_address: @ip_address, user_agent: @user_agent }
    end
  end
end

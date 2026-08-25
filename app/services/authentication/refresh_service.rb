# frozen_string_literal: true

module Authentication
  class RefreshService < ApplicationService
    private attr_reader :request_context

    def initialize(refresh_token:, user_agent:, ip_address:, request_id:)
      @refresh_token = refresh_token
      @request_context = RequestContextSanitizer.call(request_id:, user_agent:, ip_address:)
    end

    def call
      token_record = RefreshToken.find_by(token_digest: token_digest(@refresh_token))
      return invalid_refresh_token! unless token_record

      result = nil
      session = nil
      user = nil

      RefreshToken.transaction do
        session, user = lock_authenticated_records(token_record)
        next if (result = transaction_failure_result(token_record, session, user))

        result = rotate_token_pair(token_record, session, user)
      end

      handle_result(result, user:, session:)

      result
    end

    private

    def token_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    def invalid_refresh_token!
      log_event('refresh_failed', metadata: { reason: 'token_not_found' })
      raise InvalidRefreshTokenError
    end

    def lock_authenticated_records(token_record)
      token_record.lock!
      session = token_record.session.lock!
      user = session.user.lock!
      [session, user]
    end

    def transaction_failure_result(token_record, session, user)
      if token_record.rotated?
        session.revoke!
        log_event('refresh_token_reuse_detected', user: session.user, session:)
        return :reused_token
      end

      unless user.active?
        session.revoke!
        return :inactive_account
      end

      return :revoked_session if session.revoked?
      return token_record_failure(token_record) unless token_record.active?

      nil
    end

    def rotate_token_pair(token_record, session, user)
      replacement_token = RefreshTokenIssuer.call(session:)
      replacement_record = RefreshToken.find_by!(token_digest: token_digest(replacement_token))
      token_record.update!(rotated_at: Time.current, replaced_by_id: replacement_record.id)
      session.update!(
        user_agent: request_context.fetch(:user_agent),
        ip_address: request_context.fetch(:ip_address),
        last_seen_at: Time.current
      )

      result = {
        user:,
        session:,
        access_token: TokenIssuer.call(user:, session:),
        refresh_token: replacement_token
      }
      log_event('refresh_succeeded', user:, session:)
      result
    end

    def token_record_failure(token_record)
      return :expired_refresh_token if token_record.expired?

      token_record.revoked? ? :revoked_refresh_token : :invalid_refresh_token
    end

    def handle_result(result, user:, session:)
      case result
      when :reused_token
        raise InvalidRefreshTokenError
      when :inactive_account
        log_event('refresh_failed', user:, session:, metadata: { reason: 'inactive_account' })
        raise InactiveAccountError
      when :revoked_session
        log_event('refresh_failed', user:, session:, metadata: { reason: 'session_revoked' })
        raise RevokedSessionError
      when :expired_refresh_token
        log_event('refresh_failed', user:, session:, metadata: { reason: 'expired_refresh_token' })
        raise InvalidRefreshTokenError
      when :revoked_refresh_token
        log_event('refresh_failed', user:, session:, metadata: { reason: 'revoked_refresh_token' })
        raise InvalidRefreshTokenError
      when :invalid_refresh_token
        log_event('refresh_failed', user:, session:, metadata: { reason: 'invalid_refresh_token' })
        raise InvalidRefreshTokenError
      end
    end

    def log_event(event_code, user: nil, session: nil, metadata: {})
      EventLogger.call(
        event_code:,
        context: request_context,
        subject: { user:, session: },
        metadata:
      )
    end
  end
end

# frozen_string_literal: true

module Authentication
  class LoginService < ApplicationService
    DUMMY_PASSWORD_DIGEST = BCrypt::Password.create('0' * 24).freeze

    private attr_reader :request_context

    def initialize(email:, password:, user_agent:, ip_address:, request_id:)
      @email = User.normalize_email_value(email)
      @password = password
      @request_context = RequestContextSanitizer.call(request_id:, user_agent:, ip_address:)
    end

    def call
      user = User.find_for_authentication(email: @email)
      return failed_login! unless authenticated?(user)
      return inactive_account!(user) unless user.active?

      authenticate!(user)
    end

    private

    def authenticate!(user)
      result = nil

      Session.transaction do
        session = user.sessions.create!(
          user_agent: @request_context.fetch(:user_agent),
          ip_address: @request_context.fetch(:ip_address)
        )
        result = issue_tokens(user:, session:)
        log_event('login_succeeded', user:, session:)
      end

      result
    end

    def issue_tokens(user:, session:)
      access_token = TokenIssuer.call(user:, session:)
      refresh_token = RefreshTokenIssuer.call(session:)

      { user:, session:, access_token:, refresh_token: }
    end

    def failed_login!
      log_event('login_failed', identifier: @email)
      raise UnauthorizedError
    end

    def authenticated?(user)
      return user.valid_password?(@password) if user

      consume_dummy_password_digest
      false
    end

    def consume_dummy_password_digest
      BCrypt::Password.new(DUMMY_PASSWORD_DIGEST).is_password?(@password)
      nil
    end

    def inactive_account!(user)
      log_event('inactive_account_login_rejected', user:, identifier: @email)
      raise InactiveAccountError
    end

    def log_event(event_code, user: nil, session: nil, identifier: nil, metadata: {})
      EventLogger.call(
        event_code:,
        context: request_context,
        subject: { user:, session:, identifier: identifier || @email },
        metadata:
      )
    end
  end
end

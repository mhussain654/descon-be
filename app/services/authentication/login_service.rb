# frozen_string_literal: true

module Authentication
  class LoginService < ApplicationService
    def initialize(email:, password:, user_agent:, ip_address:, request_id:)
      @email = User.normalize_email_value(email)
      @password = password
      @user_agent = user_agent
      @ip_address = ip_address
      @request_id = request_id
    end

    def call
      user = User.find_for_authentication(email: @email)
      return failed_login! unless user&.valid_password?(@password)
      return inactive_account!(user) unless user.active?

      authenticate!(user)
    end

    private

    def authenticate!(user)
      result = nil

      Session.transaction do
        session = user.sessions.create!(user_agent: @user_agent, ip_address: @ip_address)
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

    def request_context
      { request_id: @request_id, ip_address: @ip_address, user_agent: @user_agent }
    end
  end
end

# frozen_string_literal: true

module Authentication
  class LoginService < ApplicationService
    def initialize(email:, password:, user_agent:, ip_address:)
      @email = email
      @password = password
      @user_agent = user_agent
      @ip_address = ip_address
    end

    def call
      user = User.find_for_authentication(email: @email)
      raise UnauthorizedError unless user&.valid_password?(@password)

      session = user.sessions.create!(user_agent: @user_agent, ip_address: @ip_address)
      issue_tokens(user:, session:)
    end

    private

    def issue_tokens(user:, session:)
      access_token = TokenIssuer.call(user:, session:)
      refresh_token = RefreshTokenIssuer.call(session:)

      { user:, session:, access_token:, refresh_token: }
    end
  end
end

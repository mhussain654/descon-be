# frozen_string_literal: true

module Authentication
  class RefreshService < ApplicationService
    def initialize(refresh_token:, user_agent:, ip_address:)
      @refresh_token = refresh_token
      @user_agent = user_agent
      @ip_address = ip_address
    end

    def call
      token_record = RefreshToken.active.find_by(token_digest: token_digest(@refresh_token))
      raise UnauthorizedError.new(message: 'Invalid refresh token.') unless token_record&.active?

      session = token_record.session
      raise UnauthorizedError.new(message: 'Session revoked.') if session.revoked?

      RefreshToken.transaction do
        replacement_token = RefreshTokenIssuer.call(session:)
        token_record.update!(rotated_at: Time.current, replaced_by_id: refresh_token_record_for(replacement_token).id)
        session.update!(user_agent: @user_agent, ip_address: @ip_address, last_seen_at: Time.current)

        {
          user: session.user,
          session:,
          access_token: TokenIssuer.call(user: session.user, session:),
          refresh_token: replacement_token
        }
      end
    end

    private

    def refresh_token_record_for(raw_token)
      RefreshToken.find_by!(token_digest: token_digest(raw_token))
    end

    def token_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end
  end
end

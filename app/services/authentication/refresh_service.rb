# frozen_string_literal: true

module Authentication
  class RefreshService < ApplicationService
    def initialize(refresh_token:, user_agent:, ip_address:)
      @refresh_token = refresh_token
      @user_agent = user_agent
      @ip_address = ip_address
    end

    def call
      token_record = RefreshToken.find_by(token_digest: token_digest(@refresh_token))
      raise UnauthorizedError.new(message: I18n.t('api.errors.invalid_refresh_token')) unless token_record

      result = nil

      RefreshToken.transaction do
        token_record.lock!
        session = token_record.session.lock!

        if token_record.rotated?
          session.revoke!
          result = :reused_token
          next
        end

        raise UnauthorizedError.new(message: I18n.t('api.errors.invalid_refresh_token')) unless token_record.active?
        raise UnauthorizedError.new(message: I18n.t('api.errors.session_revoked')) if session.revoked?

        replacement_token = RefreshTokenIssuer.call(session:)
        token_record.update!(rotated_at: Time.current, replaced_by_id: refresh_token_record_for(replacement_token).id)
        session.update!(user_agent: @user_agent, ip_address: @ip_address, last_seen_at: Time.current)

        result = {
          user: session.user,
          session:,
          access_token: TokenIssuer.call(user: session.user, session:),
          refresh_token: replacement_token
        }
      end

      raise UnauthorizedError.new(message: I18n.t('api.errors.invalid_refresh_token')) if result == :reused_token

      result
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

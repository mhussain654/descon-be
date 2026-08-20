# frozen_string_literal: true

module Authentication
  class RefreshTokenIssuer < ApplicationService
    def initialize(session:)
      @session = session
    end

    def call
      raw_token = SecureRandom.hex(48)
      @session.refresh_tokens.create!(
        token_digest: Digest::SHA256.hexdigest(raw_token),
        expires_at: RefreshToken::EXPIRY_WINDOW.from_now
      )
      raw_token
    end
  end
end

# frozen_string_literal: true

module CandidateAuthentication
  # Mirrors Authentication::RefreshTokenIssuer exactly.
  class RefreshTokenIssuer < ApplicationService
    def initialize(candidate_session:)
      @candidate_session = candidate_session
    end

    def call
      raw_token = SecureRandom.hex(48)
      @candidate_session.candidate_refresh_tokens.create!(
        token_digest: Digest::SHA256.hexdigest(raw_token),
        expires_at: CandidateRefreshToken::EXPIRY_WINDOW.from_now
      )
      raw_token
    end
  end
end

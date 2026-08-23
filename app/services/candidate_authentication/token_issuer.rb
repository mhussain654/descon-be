# frozen_string_literal: true

module CandidateAuthentication
  # Mirrors Authentication::TokenIssuer exactly, except: sub is a candidate
  # id, and `aud` is a distinct value (CANDIDATE_JWT_AUDIENCE) so a
  # candidate token can never be mistaken for -- or accidentally accepted
  # as -- a staff token even if TokenDecoder implementations were ever
  # merged, since verify_aud would reject the mismatched audience outright.
  class TokenIssuer < ApplicationService
    ACCESS_TOKEN_TTL = ENV.fetch('CANDIDATE_ACCESS_TOKEN_TTL_MINUTES', 15).to_i.minutes

    def initialize(candidate:, candidate_session:)
      @candidate = candidate
      @candidate_session = candidate_session
    end

    def call
      JWT.encode(payload, signing_secret, 'HS256')
    end

    private

    def payload
      now = Time.current.to_i

      {
        iss: jwt_issuer,
        aud: jwt_audience,
        sub: @candidate.id.to_s,
        jti: @candidate_session.jti,
        iat: now,
        exp: ACCESS_TOKEN_TTL.from_now.to_i
      }
    end

    def signing_secret
      if Rails.env.production?
        ENV.fetch('JWT_SECRET')
      else
        ENV.fetch('JWT_SECRET', Rails.application.secret_key_base)
      end
    end

    def jwt_issuer
      ENV.fetch('JWT_ISSUER', 'descon_backend')
    end

    def jwt_audience
      ENV.fetch('CANDIDATE_JWT_AUDIENCE', 'candidate_api_clients')
    end
  end
end

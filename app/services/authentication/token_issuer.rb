# frozen_string_literal: true

module Authentication
  class TokenIssuer < ApplicationService
    ACCESS_TOKEN_TTL = 15.minutes

    def initialize(user:, session:)
      @user = user
      @session = session
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
        sub: @user.id.to_s,
        jti: @session.jti,
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
      ENV.fetch('JWT_ISSUER', 'rails_api_base')
    end

    def jwt_audience
      ENV.fetch('JWT_AUDIENCE', 'rails_api_clients')
    end
  end
end

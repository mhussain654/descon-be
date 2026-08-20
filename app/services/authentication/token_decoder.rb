# frozen_string_literal: true

module Authentication
  class TokenDecoder < ApplicationService
    def initialize(token:)
      @token = token
    end

    def call
      decoded_token.first
    end

    private

    def decoded_token
      JWT.decode(@token, signing_secret, true, {
                   algorithm: 'HS256',
                   iss: jwt_issuer,
                   verify_iss: true,
                   aud: jwt_audience,
                   verify_aud: true
                 })
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

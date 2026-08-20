# frozen_string_literal: true

module Authentication
  class SessionSerializer
    def initialize(payload)
      @payload = payload
    end

    def as_json(*)
      {
        access_token: @payload.fetch(:access_token),
        refresh_token: @payload.fetch(:refresh_token),
        token_type: 'Bearer',
        expires_in: Authentication::TokenIssuer::ACCESS_TOKEN_TTL.to_i,
        session: {
          id: @payload.fetch(:session).public_id
        },
        user: Users::ProfileSerializer.new(@payload.fetch(:user)).as_json
      }
    end
  end
end

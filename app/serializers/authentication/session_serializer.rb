# frozen_string_literal: true

module Authentication
  class SessionSerializer
    def initialize(payload, message: nil)
      @payload = payload
      @message = message
    end

    def as_json(*)
      {
        access_token: @payload.fetch(:access_token),
        refresh_token: @payload.fetch(:refresh_token),
        token_type: 'Bearer',
        expires_in: Authentication::TokenIssuer::ACCESS_TOKEN_TTL.to_i,
        message: @message,
        session: session_payload,
        user: Users::ProfileSerializer.new(@payload.fetch(:user)).as_json
      }.compact
    end

    private

    def session_payload
      { id: @payload.fetch(:session).public_id }
    end
  end
end

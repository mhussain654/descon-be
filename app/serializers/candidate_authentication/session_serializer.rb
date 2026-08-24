# frozen_string_literal: true

module CandidateAuthentication
  # Mirrors Authentication::SessionSerializer's shape exactly.
  class SessionSerializer
    def initialize(payload)
      @payload = payload
    end

    def as_json(*)
      {
        access_token: @payload.fetch(:access_token),
        refresh_token: @payload.fetch(:refresh_token),
        token_type: 'Bearer',
        expires_in: CandidateAuthentication::TokenIssuer::ACCESS_TOKEN_TTL.to_i,
        session: {
          id: @payload.fetch(:candidate_session).public_id
        },
        candidate: Candidates::ProfileSerializer.new(@payload.fetch(:candidate)).as_json
      }
    end
  end
end

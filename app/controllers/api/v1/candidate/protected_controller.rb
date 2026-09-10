# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Base class for candidate-only API controllers: requires an authenticated candidate
      # (via bearer token), enforces that every action performs Pundit authorization, and
      # exposes the current candidate as the Pundit user.
      class ProtectedController < BaseController
        before_action :authenticate_current_candidate!
        before_action :ensure_consent_given!
        after_action :verify_authorized

        private

        attr_reader :current_candidate_session

        # Resolves and memoizes the authenticated Candidate from the bearer token, validating that
        # the session is active and the account is active, and raising UnauthorizedError otherwise.
        def current_candidate
          @current_candidate ||= begin
            @current_candidate_session = candidate_session_from_token
            raise UnauthorizedError if @current_candidate_session.revoked?

            @current_candidate_session.touch_last_seen!
            candidate = ::Candidate.find(decoded_bearer_payload.fetch('sub'))
            raise InactiveAccountError unless candidate.active_for_authentication?

            candidate
          rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound
            raise UnauthorizedError
          end
        end

        # before_action hook that forces authentication by resolving the current candidate (or raising).
        def authenticate_current_candidate!
          current_candidate
        end

        # Tells Pundit to authorize against the current candidate rather than a staff user.
        def pundit_user
          current_candidate
        end

        # before_action hook that blocks every candidate endpoint until the current policy
        # version has been accepted -- except the consents endpoint itself, which must stay
        # reachable so the candidate can actually submit that acceptance while gated.
        # Subclasses that legitimately need to run before consent is given (only the consents
        # controller) skip this via `skip_before_action :ensure_consent_given!`.
        def ensure_consent_given!
          raise ConsentRequiredError unless CandidateConsent.current_policy_accepted?(current_candidate)
        end

        # Extracts the raw JWT from the Authorization header, raising UnauthorizedError if the
        # scheme isn't "Bearer" or the token is missing.
        def bearer_token
          scheme, token = request.headers['Authorization'].to_s.split(' ', 2)
          raise UnauthorizedError if scheme != 'Bearer' || token.blank?

          token
        end

        # Decodes and memoizes the bearer token's JWT payload.
        def decoded_bearer_payload
          @decoded_bearer_payload ||= CandidateAuthentication::TokenDecoder.call(token: bearer_token)
        end

        # Looks up the active CandidateSession matching the token's jti and verifies it belongs
        # to the same candidate encoded in the token.
        def candidate_session_from_token
          session = ::CandidateSession.active.find_by!(jti: decoded_bearer_payload.fetch('jti'))
          raise UnauthorizedError if session.candidate_id.to_s != decoded_bearer_payload.fetch('sub')

          session
        rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound
          raise UnauthorizedError
        end
      end
    end
  end
end

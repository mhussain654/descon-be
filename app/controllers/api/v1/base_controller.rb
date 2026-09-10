# frozen_string_literal: true

module Api
  module V1
    # Base class for staff-facing (internal user) API controllers: provides bearer-token
    # authentication and resolves the current authenticated staff user and session.
    class BaseController < ApplicationController
      private

      attr_reader :current_session

      # Resolves and memoizes the authenticated staff User from the bearer token, validating that
      # the session is active and the account is active, and raising UnauthorizedError otherwise.
      def current_user
        @current_user ||= begin
          @current_session = session_from_token
          raise UnauthorizedError if @current_session.revoked?

          @current_session.touch_last_seen!
          user = User.find(decoded_bearer_payload.fetch('sub'))
          raise InactiveAccountError unless user.active_staff_account?

          user
        rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound
          raise UnauthorizedError
        end
      end

      # before_action hook that forces authentication by resolving the current user (or raising).
      def authenticate_current_user!
        current_user
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
        @decoded_bearer_payload ||= Authentication::TokenDecoder.call(token: bearer_token)
      end

      # Looks up the Session matching the token's jti, optionally including revoked sessions,
      # and verifies it belongs to the same user encoded in the token.
      def session_from_token(allow_revoked: false)
        session_scope = allow_revoked ? Session.all : Session.active
        session = session_scope.find_by!(jti: decoded_bearer_payload.fetch('jti'))
        raise UnauthorizedError if session.user_id.to_s != decoded_bearer_payload.fetch('sub')

        session
      rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound
        raise UnauthorizedError
      end
    end
  end
end

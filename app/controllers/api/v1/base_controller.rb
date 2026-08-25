# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      private

      attr_reader :current_session

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

      def authenticate_current_user!
        current_user
      end

      def bearer_token
        scheme, token = request.headers['Authorization'].to_s.split(' ', 2)
        raise UnauthorizedError if scheme != 'Bearer' || token.blank?

        token
      end

      def decoded_bearer_payload
        @decoded_bearer_payload ||= Authentication::TokenDecoder.call(token: bearer_token)
      end

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

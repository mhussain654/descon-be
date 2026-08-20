# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      private

      attr_reader :current_session

      def current_user
        @current_user ||= begin
          payload = Authentication::TokenDecoder.call(token: bearer_token)
          @current_session = Session.active.find_by!(jti: payload.fetch('jti'))
          raise UnauthorizedError if @current_session.user_id.to_s != payload.fetch('sub')

          @current_session.touch_last_seen!
          User.find(payload.fetch('sub'))
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
    end
  end
end

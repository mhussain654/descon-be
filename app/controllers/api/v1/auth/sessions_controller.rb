# frozen_string_literal: true

module Api
  module V1
    module Auth
      class SessionsController < BaseController
        def create
          result = Authentication::LoginService.call(
            email: login_params.fetch(:email),
            password: login_params.fetch(:password),
            user_agent: request.user_agent,
            ip_address: request.remote_ip
          )

          render_success(data: Authentication::SessionSerializer.new(result).as_json, status: :created)
        end

        def refresh
          result = Authentication::RefreshService.call(
            refresh_token: refresh_params.fetch(:refresh_token),
            user_agent: request.user_agent,
            ip_address: request.remote_ip
          )

          render_success(data: Authentication::SessionSerializer.new(result).as_json)
        end

        def destroy
          session = session_from_token(allow_revoked: true)

          render_idempotent_response(scope: 'auth.logout', subject: session) do
            raise UnauthorizedError if session.revoked?

            Authentication::LogoutService.call(session:)
            success_payload(data: { revoked: true })
          end
        end

        private

        def login_params
          params.expect(auth: %i[email password])
        end

        def refresh_params
          params.expect(auth: [:refresh_token])
        end
      end
    end
  end
end

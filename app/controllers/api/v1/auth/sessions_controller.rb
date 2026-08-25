# frozen_string_literal: true

module Api
  module V1
    module Auth
      class SessionsController < BaseController
        def create
          result = Authentication::LoginService.call(**login_service_params)
          render_success(
            data: serialized_session(result, message: t('api.authentication.login_succeeded')),
            status: :created
          )
        end

        def refresh
          result = Authentication::RefreshService.call(**refresh_service_params)
          render_success(data: serialized_session(result, message: t('api.authentication.refresh_succeeded')))
        end

        def destroy
          session = session_from_token(allow_revoked: true)

          render_idempotent_response(scope: 'auth.logout', subject: session) do
            Authentication::LogoutService.call(
              session:,
              request_id: request.request_id,
              ip_address: request.remote_ip,
              user_agent: request.user_agent
            )
            success_payload(data: { revoked: true, message: t('api.authentication.logout_succeeded') })
          end
        end

        private

        def login_params
          params.expect(auth: %i[email password])
        end

        def refresh_params
          params.expect(auth: [:refresh_token])
        end

        def login_service_params
          {
            email: login_params.fetch(:email),
            password: login_params.fetch(:password),
            user_agent: request.user_agent,
            ip_address: request.remote_ip,
            request_id: request.request_id
          }
        end

        def refresh_service_params
          {
            refresh_token: refresh_params.fetch(:refresh_token),
            user_agent: request.user_agent,
            ip_address: request.remote_ip,
            request_id: request.request_id
          }
        end

        def serialized_session(result, message:)
          Authentication::SessionSerializer.new(result, message:).as_json
        end
      end
    end
  end
end

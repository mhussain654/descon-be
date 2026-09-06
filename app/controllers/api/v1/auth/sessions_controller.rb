# frozen_string_literal: true

module Api
  module V1
    module Auth
      # Handles staff login, token refresh, and logout for the internal (non-candidate) auth flow.
      class SessionsController < BaseController
        # Authenticates a staff user by email/password and returns a new access/refresh token pair.
        def create
          result = Authentication::LoginService.call(**login_service_params)
          render_success(
            data: serialized_session(result, message: t('api.authentication.login_succeeded')),
            status: :created
          )
        end

        # Exchanges a valid refresh token for a new access/refresh token pair.
        def refresh
          result = Authentication::RefreshService.call(**refresh_service_params)
          render_success(data: serialized_session(result, message: t('api.authentication.refresh_succeeded')))
        end

        # Revokes the current session (logout), including an already-revoked session so the
        # request is safely idempotent; replays via Idempotency-Key are supported.
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

        # Strong-params the login credentials.
        def login_params
          params.expect(auth: %i[email password])
        end

        # Strong-params the refresh token.
        def refresh_params
          params.expect(auth: [:refresh_token])
        end

        # Builds the argument hash passed to the login service, including request/client metadata.
        def login_service_params
          {
            email: login_params.fetch(:email),
            password: login_params.fetch(:password),
            user_agent: request.user_agent,
            ip_address: request.remote_ip,
            request_id: request.request_id
          }
        end

        # Builds the argument hash passed to the refresh service, including request/client metadata.
        def refresh_service_params
          {
            refresh_token: refresh_params.fetch(:refresh_token),
            user_agent: request.user_agent,
            ip_address: request.remote_ip,
            request_id: request.request_id
          }
        end

        # Serializes a login/refresh result (tokens plus user) into the response body.
        def serialized_session(result, message:)
          Authentication::SessionSerializer.new(result, message:).as_json
        end
      end
    end
  end
end

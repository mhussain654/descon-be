# frozen_string_literal: true

module Api
  module V1
    module Candidate
      module Auth
        # Lets a candidate app renew its short-lived access token without a new SMS OTP.
        class SessionsController < Candidate::BaseController
          # Exchanges a valid refresh token for a new access/refresh token pair.
          def refresh
            result = CandidateAuthentication::RefreshService.call(
              refresh_token: refresh_params.fetch(:refresh_token),
              user_agent: request.user_agent,
              ip_address: request.remote_ip
            )

            render_success(data: CandidateAuthentication::SessionSerializer.new(result).as_json)
          end

          private

          # Allowlists the refresh token field from the request body.
          def refresh_params
            params.expect(candidate: [:refresh_token])
          end
        end
      end
    end
  end
end

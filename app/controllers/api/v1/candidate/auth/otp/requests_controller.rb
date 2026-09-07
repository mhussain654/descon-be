# frozen_string_literal: true

module Api
  module V1
    module Candidate
      module Auth
        module Otp
          # Lets an unauthenticated candidate request a one-time login code for their CNIC.
          class RequestsController < Candidate::BaseController
            # Triggers sending a fresh OTP for the given CNIC and returns the request outcome
            # (never reveals whether the CNIC is actually registered).
            def create
              result = CandidateAuthentication::Otp::RequestService.call(
                cnic: otp_request_params.fetch(:cnic),
                ip_address: request.remote_ip
              )

              render_success(data: result)
            end

            private

            # Allowlists the CNIC field from the request body.
            def otp_request_params
              params.expect(candidate: [:cnic])
            end
          end
        end
      end
    end
  end
end

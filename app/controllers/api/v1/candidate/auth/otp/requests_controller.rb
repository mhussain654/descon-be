# frozen_string_literal: true

module Api
  module V1
    module Candidate
      module Auth
        module Otp
          class RequestsController < Candidate::BaseController
            def create
              result = CandidateAuthentication::Otp::RequestService.call(
                cnic: otp_request_params.fetch(:cnic),
                ip_address: request.remote_ip
              )

              render_success(data: result)
            end

            private

            def otp_request_params
              params.expect(candidate: [:cnic])
            end
          end
        end
      end
    end
  end
end

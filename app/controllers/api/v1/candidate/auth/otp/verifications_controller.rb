# frozen_string_literal: true

module Api
  module V1
    module Candidate
      module Auth
        module Otp
          class VerificationsController < Candidate::BaseController
            def create
              result = CandidateAuthentication::Otp::VerifyService.call(
                cnic: otp_verify_params.fetch(:cnic),
                code: otp_verify_params.fetch(:otp),
                user_agent: request.user_agent,
                ip_address: request.remote_ip
              )

              render_success(data: CandidateAuthentication::SessionSerializer.new(result).as_json, status: :created)
            end

            private

            def otp_verify_params
              params.expect(candidate: %i[cnic otp])
            end
          end
        end
      end
    end
  end
end

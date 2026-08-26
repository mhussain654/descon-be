# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class ProtectedController < BaseController
        before_action :authenticate_current_candidate!
        after_action :verify_authorized

        private

        attr_reader :current_candidate_session

        def current_candidate
          @current_candidate ||= begin
            @current_candidate_session = candidate_session_from_token
            raise UnauthorizedError if @current_candidate_session.revoked?

            @current_candidate_session.touch_last_seen!
            candidate = ::Candidate.find(decoded_bearer_payload.fetch('sub'))
            raise InactiveAccountError unless candidate.active_for_authentication?

            candidate
          rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound
            raise UnauthorizedError
          end
        end

        def authenticate_current_candidate!
          current_candidate
        end

        def pundit_user
          current_candidate
        end

        def bearer_token
          scheme, token = request.headers['Authorization'].to_s.split(' ', 2)
          raise UnauthorizedError if scheme != 'Bearer' || token.blank?

          token
        end

        def decoded_bearer_payload
          @decoded_bearer_payload ||= CandidateAuthentication::TokenDecoder.call(token: bearer_token)
        end

        def candidate_session_from_token
          session = ::CandidateSession.active.find_by!(jti: decoded_bearer_payload.fetch('jti'))
          raise UnauthorizedError if session.candidate_id.to_s != decoded_bearer_payload.fetch('sub')

          session
        rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound
          raise UnauthorizedError
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    class UserInvitationsController < BaseController
      def update
        render_success(data: invitation_acceptance_payload)
      end

      private

      def invitation_params
        params.expect(invitation: %i[token password password_confirmation])
      end

      def invitation_acceptance_payload
        user = ::Users::InvitationAcceptanceService.call(
          token: invitation_params.fetch(:token),
          password: invitation_params.fetch(:password),
          password_confirmation: invitation_params.fetch(:password_confirmation),
          request_id: request.request_id
        )
        { user: ::Users::SummarySerializer.new(user).as_json, message: t('api.users.invitation_accepted') }
      end
    end
  end
end

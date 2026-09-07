# frozen_string_literal: true

module Api
  module V1
    # Lets a staff user with a valid invitation token set their password and activate their account.
    # Unauthenticated by design since the invitation token itself is the credential.
    class UserInvitationsController < BaseController
      # Accepts a pending invitation by setting the new user's password, returning the activated user.
      def update
        render_success(data: invitation_acceptance_payload)
      end

      private

      # Strong-params the invitation token and new password fields.
      def invitation_params
        params.expect(invitation: %i[token password password_confirmation])
      end

      # Activates the invited account via the invitation service and builds the success response body.
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

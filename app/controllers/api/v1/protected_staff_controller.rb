# frozen_string_literal: true

module Api
  module V1
    # Base class for staff-only API controllers: requires an authenticated staff user and
    # enforces that every action performs Pundit authorization (and scoping for index actions).
    class ProtectedStaffController < BaseController
      before_action :authenticate_current_user!
      after_action :verify_staff_pundit_usage!

      private

      # Fails the request if the action didn't call authorize (and, for index actions, policy_scope).
      def verify_staff_pundit_usage!
        verify_authorized
        verify_policy_scoped if action_name == 'index'
      end
    end
  end
end

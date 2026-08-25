# frozen_string_literal: true

module Api
  module V1
    class ProtectedStaffController < BaseController
      before_action :authenticate_current_user!
      after_action :verify_staff_pundit_usage!

      private

      def verify_staff_pundit_usage!
        verify_authorized
        verify_policy_scoped if action_name == 'index'
      end
    end
  end
end

# frozen_string_literal: true

module Admin
  class ManagementDashboardPolicy < ApplicationPolicy
    def show?
      permission_granted?('view_management_dashboard')
    end
  end
end

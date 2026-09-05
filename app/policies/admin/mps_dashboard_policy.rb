# frozen_string_literal: true

module Admin
  class MpsDashboardPolicy < ApplicationPolicy
    def show?
      permission_granted?('view_mps_dashboard')
    end
  end
end

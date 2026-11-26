# frozen_string_literal: true

module Admin
  # Candidate campaigns: every active staff member may list them (to pick a
  # working campaign on their profile); creating one is part of managing
  # candidates (imports, the New candidate form).
  class CampaignPolicy < ApplicationPolicy
    def index? = staff_authenticated?

    def create? = permission_granted?('manage_candidates')

    class Scope < Scope
      def resolve
        staff_authenticated? ? scope.all : scope.none
      end
    end
  end
end

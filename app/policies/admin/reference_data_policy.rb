# frozen_string_literal: true

module Admin
  # Shared authorization for the read-only lookup endpoints (countries,
  # projects, crafts) that populate candidate-creation/assignment forms --
  # visible to anyone who can view or manage candidates, since choosing a
  # candidate's project/country/craft is part of both flows.
  class ReferenceDataPolicy < ApplicationPolicy
    def index?
      permission_granted?('view_candidates') || permission_granted?('manage_candidates')
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('view_candidates') || permission_granted?('manage_candidates')

        scope.active
      end
    end
  end
end

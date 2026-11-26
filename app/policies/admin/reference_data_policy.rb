# frozen_string_literal: true

module Admin
  # Countries, projects and crafts. Listing the active ones (for candidate
  # forms) is open to anyone who can view or manage candidates; managing them
  # -- the full list with retired ones, add, edit, retire, restore, delete --
  # is developer-only (`manage_reference_data`).
  class ReferenceDataPolicy < ApplicationPolicy
    def index?
      permission_granted?('view_candidates') || permission_granted?('manage_candidates')
    end

    def create?
      permission_granted?('manage_reference_data')
    end

    def update?
      permission_granted?('manage_reference_data')
    end

    def retire?
      permission_granted?('manage_reference_data')
    end

    def manage? = permission_granted?('manage_reference_data')
    def restore? = manage?
    def destroy? = manage?

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('view_candidates') || permission_granted?('manage_candidates')

        scope.active
      end
    end

    # Every row, for developers managing reference data (roles, checklists,
    # stages, processes); nothing for anyone else.
    class ManagedScope < Scope
      def resolve
        permission_granted?('manage_reference_data') ? scope.all : scope.none
      end
    end
  end
end

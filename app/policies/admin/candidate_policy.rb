# frozen_string_literal: true

module Admin
  class CandidatePolicy < ApplicationPolicy
    def index?
      show?
    end

    def show?
      permission_granted?('view_candidates') || permission_granted?('manage_candidates')
    end

    def create?
      permission_granted?('manage_candidates')
    end

    def update?
      permission_granted?('manage_candidates')
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('view_candidates') || permission_granted?('manage_candidates')

        scope.all
      end
    end
  end
end

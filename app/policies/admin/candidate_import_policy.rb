# frozen_string_literal: true

module Admin
  class CandidateImportPolicy < ApplicationPolicy
    def index?
      permission_granted?('manage_candidates')
    end

    def show?
      permission_granted?('manage_candidates')
    end

    def create?
      permission_granted?('manage_candidates')
    end

    alias preflight? create?
    alias commit? create?
    alias error_export? show?
    alias retry? show?

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('manage_candidates')

        scope.where(actor: user)
      end
    end
  end
end

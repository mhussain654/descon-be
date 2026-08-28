# frozen_string_literal: true

module Admin
  class CandidateBankDetailPolicy < ApplicationPolicy
    def show?
      view_masked?
    end

    def access_proof?
      view_unmasked?
    end

    def view_unmasked?
      permission_granted?('manage_payments')
    end

    def view_masked?
      permission_granted?('view_payments') || view_unmasked?
    end

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('view_payments') || permission_granted?('manage_payments')

        scope.current_version
      end
    end
  end
end

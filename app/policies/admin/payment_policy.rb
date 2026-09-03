# frozen_string_literal: true

module Admin
  class PaymentPolicy < ApplicationPolicy
    def index? = permission_granted?('view_payments') || permission_granted?('manage_payments')
    def show?  = index?
    def create_correction? = permission_granted?('manage_payments')

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('view_payments') || permission_granted?('manage_payments')

        scope.all
      end
    end
  end
end

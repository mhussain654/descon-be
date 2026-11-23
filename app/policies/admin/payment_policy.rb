# frozen_string_literal: true

module Admin
  class PaymentPolicy < ApplicationPolicy
    def index? = permission_granted?('view_payments') || permission_granted?('manage_payments')
    def show?  = index?
    def create_correction? = permission_granted?('manage_payments')
    # Developers only: marking a fee paid that KuickPay took but the system never recorded.
    def record_manual? = permission_granted?('record_manual_payment')

    class Scope < Scope
      def resolve
        return scope.none unless permission_granted?('view_payments') || permission_granted?('manage_payments')

        scope.all
      end
    end
  end
end

# frozen_string_literal: true

module Admin
  class OnboardingFeePolicy < ApplicationPolicy
    def show? = permission_granted?('view_payments') || permission_granted?('manage_payments')
    def update? = permission_granted?('manage_payments')
  end
end

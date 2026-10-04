# frozen_string_literal: true

module Payments
  # Active bills and settled payments keep their original amount. An override
  # belongs to the current assignment, so it cannot leak into a later placement.
  class FeeResolver
    def self.committed_payment(assignment)
      return if assignment.blank?

      assignment.payments.where(payment_type_code: 'onboarding_fee')
                .where('status_code = :paid OR (status_code = :pending AND checkout_expires_at > :now)',
                       paid: 'paid', pending: 'checkout_pending', now: Time.current)
                .latest_first.first
    end

    def self.amount(assignment)
      committed_payment(assignment)&.amount || assignment&.onboarding_fee_amount || OnboardingFeeSetting.current.amount
    end
  end
end

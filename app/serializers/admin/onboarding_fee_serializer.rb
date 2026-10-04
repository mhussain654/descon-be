# frozen_string_literal: true

module Admin
  class OnboardingFeeSerializer
    def initialize(setting:, assignment: nil)
      @setting = setting
      @assignment = assignment
    end

    def as_json(*)
      amount_attributes.merge(state_attributes)
    end

    private

    def amount_attributes
      {
        default_amount: money(@setting.amount),
        override_amount: @assignment&.onboarding_fee_amount && money(@assignment.onboarding_fee_amount),
        effective_amount: money(effective_amount),
        currency_code: ::Payments::Configuration.new.currency_code
      }
    end

    def state_attributes
      {
        version: @assignment ? @assignment.fee_version : @setting.lock_version,
        assignment_id: @assignment&.public_id,
        locked: @assignment.present? && ::Payments::FeeResolver.committed_payment(@assignment).present?,
        updated_at: (@assignment || @setting).updated_at.iso8601(6)
      }
    end

    def effective_amount
      @assignment ? ::Payments::FeeResolver.amount(@assignment) : @setting.amount
    end

    def money(amount) = format('%.2f', amount)
  end
end

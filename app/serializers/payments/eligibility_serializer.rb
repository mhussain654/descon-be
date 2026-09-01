# frozen_string_literal: true

module Payments
  class EligibilitySerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        eligible: @result.eligible,
        checkout_available: @result.checkout_available,
        required_stage_code: @result.required_stage_code,
        current_stage_code: @result.current_stage_code,
        blocking_reasons: @result.blocking_reasons,
        amount: @result.amount.to_s('F'),
        currency_code: @result.currency_code,
        latest_payment: serialized_payment
      }
    end

    private

    def serialized_payment
      return if @result.latest_payment.blank?

      Payments::PaymentSerializer.new(@result.latest_payment).as_json
    end
  end
end

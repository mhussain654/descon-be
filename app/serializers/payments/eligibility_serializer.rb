# frozen_string_literal: true

module Payments
  class EligibilitySerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      availability_attributes.merge(
        required_stage_code: @result.required_stage_code,
        current_stage_code: @result.current_stage_code,
        blocking_reasons: @result.blocking_reasons,
        amount: @result.amount.to_s('F'),
        currency_code: @result.currency_code,
        latest_payment: serialized_payment
      )
    end

    private

    # Which ways of paying are offered, and the ones already started: the open payment
    # code (with its number) and whether a card checkout is open. Both may be open; the
    # candidate chooses, and the screen warns them to pay only one.
    def availability_attributes
      {
        eligible: @result.eligible,
        checkout_available: @result.checkout_available,
        voucher_available: @result.voucher_available,
        open_voucher: serialized(@result.open_voucher),
        card_checkout_open: @result.card_checkout_open
      }
    end

    def serialized_payment = serialized(@result.latest_payment)

    def serialized(payment)
      Payments::PaymentSerializer.new(payment).as_json if payment.present?
    end
  end
end

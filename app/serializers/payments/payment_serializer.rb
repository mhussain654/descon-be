# frozen_string_literal: true

module Payments
  class PaymentSerializer
    def initialize(payment)
      @payment = payment
    end

    def as_json(*) = base_attributes.merge(timestamp_attributes).compact

    private

    def base_attributes
      {
        id: @payment.public_id,
        payment_type_code: @payment.payment_type_code,
        status: @payment.status_code,
        amount: @payment.amount.to_s('F'),
        currency_code: @payment.currency_code,
        provider: @payment.provider_code,
        checkout_url: @payment.checkout_url
      }
    end

    def timestamp_attributes
      {
        checkout_expires_at: @payment.checkout_expires_at&.utc&.iso8601,
        paid_at: @payment.paid_at&.utc&.iso8601,
        updated_at: @payment.updated_at&.utc&.iso8601
      }
    end
  end
end

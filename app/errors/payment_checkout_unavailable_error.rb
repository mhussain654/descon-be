# frozen_string_literal: true

class PaymentCheckoutUnavailableError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.payment_checkout_unavailable')
    super(code: 'payment_checkout_unavailable', message:, status: :service_unavailable)
  end
end

# frozen_string_literal: true

class PaymentNotFoundError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.payment_not_found')
    super(code: 'payment_not_found', message:, status: :not_found)
  end
end

# frozen_string_literal: true

class PaymentNotEligibleError < BaseError
  def initialize(field: 'payment', details: nil, message: nil)
    message ||= I18n.t('api.errors.payment_not_eligible')
    super(code: 'payment_not_eligible', message:, status: :unprocessable_content, field:, details:)
  end
end

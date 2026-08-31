# frozen_string_literal: true

class PaymentSignatureInvalidError < BaseError
  def initialize(field: 'payment_notification.signature', message: nil)
    message ||= I18n.t('api.errors.payment_signature_invalid')
    super(code: 'payment_signature_invalid', message:, status: :unauthorized, field:)
  end
end

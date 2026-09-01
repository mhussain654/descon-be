# frozen_string_literal: true

class PaymentNotificationMismatchError < BaseError
  def initialize(field:, details: nil, message: nil)
    message ||= I18n.t('api.errors.payment_notification_mismatch')
    super(code: 'payment_notification_mismatch', message:, status: :unprocessable_content, field:, details:)
  end
end

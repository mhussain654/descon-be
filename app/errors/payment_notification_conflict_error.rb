# frozen_string_literal: true

class PaymentNotificationConflictError < BaseError
  def initialize(field: 'payment_notification', details: nil, message: nil)
    message ||= I18n.t('api.errors.payment_notification_conflict')
    super(code: 'payment_notification_conflict', message:, status: :conflict, field:, details:)
  end
end

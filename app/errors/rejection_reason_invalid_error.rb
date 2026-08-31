# frozen_string_literal: true

class RejectionReasonInvalidError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.rejection_reason_invalid')
    super(code: 'rejection_reason_invalid', message:, status: :unprocessable_content, field: 'rejection.reason')
  end
end

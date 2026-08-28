# frozen_string_literal: true

class RejectionReasonRequiredError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.rejection_reason_required')
    super(code: 'rejection_reason_required', message:, status: :unprocessable_entity, field: 'rejection.reason')
  end
end

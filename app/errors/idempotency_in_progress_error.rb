# frozen_string_literal: true

class IdempotencyInProgressError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.idempotency_in_progress')
    super(code: 'idempotency_in_progress', message:, status: :conflict)
  end
end

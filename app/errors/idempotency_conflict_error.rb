# frozen_string_literal: true

class IdempotencyConflictError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.idempotency_conflict')
    super(code: 'idempotency_conflict', message:, status: :conflict)
  end
end

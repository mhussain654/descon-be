# frozen_string_literal: true

class InvalidIdempotencyKeyError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.invalid_idempotency_key')
    super(code: 'invalid_idempotency_key', message:, status: :bad_request, field: 'idempotency_key')
  end
end

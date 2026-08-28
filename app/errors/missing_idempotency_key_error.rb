# frozen_string_literal: true

class MissingIdempotencyKeyError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.missing_idempotency_key')
    super(code: 'missing_idempotency_key', message:, status: :bad_request, field: 'idempotency_key')
  end
end

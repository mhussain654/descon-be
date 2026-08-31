# frozen_string_literal: true

class ValidationError < BaseError
  def initialize(message: nil, field: nil)
    message ||= I18n.t('api.errors.validation_failed')
    super(code: 'validation_failed', message:, status: :unprocessable_content, field:)
  end
end

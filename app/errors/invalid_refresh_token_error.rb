# frozen_string_literal: true

class InvalidRefreshTokenError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.invalid_refresh_token')
    super(code: 'invalid_refresh_token', message:, status: :unauthorized)
  end
end

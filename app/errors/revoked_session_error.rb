# frozen_string_literal: true

class RevokedSessionError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.session_revoked')
    super(code: 'session_revoked', message:, status: :unauthorized)
  end
end

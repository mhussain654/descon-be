# frozen_string_literal: true

class InternalServerError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.internal_server_error')
    super(code: 'internal_server_error', message:, status: :internal_server_error)
  end
end

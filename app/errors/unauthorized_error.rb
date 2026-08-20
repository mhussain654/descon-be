# frozen_string_literal: true

class UnauthorizedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.unauthorized')
    super(code: 'unauthorized', message:, status: :unauthorized)
  end
end

# frozen_string_literal: true

class ForbiddenError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.forbidden')
    super(code: 'forbidden', message:, status: :forbidden)
  end
end

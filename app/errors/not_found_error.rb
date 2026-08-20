# frozen_string_literal: true

class NotFoundError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.not_found')
    super(code: 'not_found', message:, status: :not_found)
  end
end

# frozen_string_literal: true

class BadRequestError < BaseError
  def initialize(message: nil, field: nil)
    message ||= I18n.t('api.errors.bad_request')
    super(code: 'bad_request', message:, status: :bad_request, field:)
  end
end

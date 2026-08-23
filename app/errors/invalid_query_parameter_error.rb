# frozen_string_literal: true

class InvalidQueryParameterError < BaseError
  def initialize(field:, message: nil)
    message ||= I18n.t('api.errors.invalid_query_parameter')
    super(code: 'invalid_query_parameter', message:, status: :bad_request, field:)
  end
end

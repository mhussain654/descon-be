# frozen_string_literal: true

class UnsupportedFilterError < BaseError
  def initialize(filter_name:, message: nil)
    message ||= I18n.t('api.errors.unsupported_filter')
    super(code: 'unsupported_filter', message:, status: :bad_request, field: "filter.#{filter_name}")
  end
end

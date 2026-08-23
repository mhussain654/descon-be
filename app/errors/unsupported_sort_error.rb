# frozen_string_literal: true

class UnsupportedSortError < BaseError
  def initialize(sort_name:, message: nil)
    message ||= I18n.t('api.errors.unsupported_sort')
    super(code: 'unsupported_sort', message:, status: :bad_request, field: "sort.#{sort_name}")
  end
end

# frozen_string_literal: true

class ReviewNotAllowedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.review_not_allowed')
    super(code: 'review_not_allowed', message:, status: :forbidden)
  end
end

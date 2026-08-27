# frozen_string_literal: true

class SubmissionNotAllowedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.submission_not_allowed')
    super(code: 'submission_not_allowed', message:, status: :unprocessable_entity)
  end
end

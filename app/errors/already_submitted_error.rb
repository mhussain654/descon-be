# frozen_string_literal: true

class AlreadySubmittedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.already_submitted')
    super(code: 'already_submitted', message:, status: :unprocessable_content)
  end
end

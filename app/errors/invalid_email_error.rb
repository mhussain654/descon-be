# frozen_string_literal: true

class InvalidEmailError < BaseError
  def initialize
    super(
      code: 'invalid_email',
      message: I18n.t('api.errors.invalid_email'),
      status: :unprocessable_content,
      field: 'candidate_profile.email'
    )
  end
end

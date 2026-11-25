# frozen_string_literal: true

class InvalidEmailError < BaseError
  def initialize(field: 'candidate_profile.email')
    super(
      code: 'invalid_email',
      message: I18n.t('api.errors.invalid_email'),
      status: :unprocessable_content,
      field:
    )
  end
end

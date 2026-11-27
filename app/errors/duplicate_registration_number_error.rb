# frozen_string_literal: true

class DuplicateRegistrationNumberError < BaseError
  def initialize
    super(
      code: 'duplicate_registration_number',
      message: I18n.t('api.errors.duplicate_registration_number'),
      status: :unprocessable_content,
      field: 'registration_number'
    )
  end
end

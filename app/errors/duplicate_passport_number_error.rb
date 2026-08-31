# frozen_string_literal: true

class DuplicatePassportNumberError < BaseError
  def initialize
    super(
      code: 'duplicate_passport_number',
      message: I18n.t('api.errors.duplicate_passport_number'),
      status: :unprocessable_content,
      field: 'passport_number'
    )
  end
end

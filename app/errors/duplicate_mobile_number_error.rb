# frozen_string_literal: true

class DuplicateMobileNumberError < BaseError
  def initialize
    super(
      code: 'duplicate_mobile_number',
      message: I18n.t('api.errors.duplicate_mobile_number'),
      status: :unprocessable_content,
      field: 'mobile_number'
    )
  end
end

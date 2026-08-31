# frozen_string_literal: true

class InvalidAccountNumberError < BaseError
  def initialize
    super(
      code: 'invalid_account_number',
      message: I18n.t('api.errors.invalid_account_number'),
      status: :unprocessable_content,
      field: 'bank_detail.account_number'
    )
  end
end

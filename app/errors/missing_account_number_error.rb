# frozen_string_literal: true

class MissingAccountNumberError < BaseError
  def initialize
    super(
      code: 'missing_account_number',
      message: I18n.t('api.errors.missing_account_number'),
      status: :unprocessable_entity,
      field: 'bank_detail.account_number'
    )
  end
end

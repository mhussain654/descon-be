# frozen_string_literal: true

class MissingBankNameError < BaseError
  def initialize
    super(
      code: 'missing_bank_name',
      message: I18n.t('api.errors.missing_bank_name'),
      status: :unprocessable_content,
      field: 'bank_detail.bank_name'
    )
  end
end

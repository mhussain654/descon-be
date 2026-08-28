# frozen_string_literal: true

class MissingAccountTitleError < BaseError
  def initialize
    super(
      code: 'missing_account_title',
      message: I18n.t('api.errors.missing_account_title'),
      status: :unprocessable_entity,
      field: 'bank_detail.account_title'
    )
  end
end

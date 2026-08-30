# frozen_string_literal: true

class MissingBankProofError < BaseError
  def initialize
    super(
      code: 'missing_proof',
      message: I18n.t('api.errors.missing_proof'),
      status: :unprocessable_entity,
      field: 'bank_detail.proof'
    )
  end
end

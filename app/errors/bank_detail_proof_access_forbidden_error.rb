# frozen_string_literal: true

class BankDetailProofAccessForbiddenError < BaseError
  def initialize
    super(
      code: 'bank_detail_proof_access_forbidden',
      message: I18n.t('api.errors.bank_detail_proof_access_forbidden'),
      status: :forbidden
    )
  end
end

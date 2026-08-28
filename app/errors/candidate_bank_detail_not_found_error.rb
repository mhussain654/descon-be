# frozen_string_literal: true

class CandidateBankDetailNotFoundError < BaseError
  def initialize
    super(
      code: 'candidate_bank_detail_not_found',
      message: I18n.t('api.errors.candidate_bank_detail_not_found'),
      status: :not_found
    )
  end
end

# frozen_string_literal: true

# A candidate tried to change bank details staff have already verified.
class BankDetailAlreadyVerifiedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.bank_detail_already_verified')
    super(code: 'bank_detail_already_verified', message:, status: :unprocessable_content)
  end
end

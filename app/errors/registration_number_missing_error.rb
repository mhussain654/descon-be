# frozen_string_literal: true

# A KuickPay voucher is asked for a candidate who has no registration (file) number yet: the voucher's
# registration number, and so the candidate's Kuickpay ID, is that number.
class RegistrationNumberMissingError < BaseError
  def initialize
    super(
      code: 'registration_number_missing',
      message: I18n.t('api.errors.registration_number_missing'),
      status: :unprocessable_content,
      field: 'registration_number'
    )
  end
end

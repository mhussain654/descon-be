# frozen_string_literal: true

# A developer tried to mark a fee paid for a candidate who is not at Fee
# Pending, has no current assignment, or has already paid.
class ManualPaymentNotAllowedError < BaseError
  def initialize
    super(code: 'manual_payment_not_allowed', message: I18n.t('api.errors.manual_payment_not_allowed'),
          status: :unprocessable_content)
  end
end

# frozen_string_literal: true

class StalePaymentError < BaseError
  def initialize
    super(
      code: 'stale_payment',
      message: I18n.t('api.errors.stale_payment'),
      status: :conflict
    )
  end
end

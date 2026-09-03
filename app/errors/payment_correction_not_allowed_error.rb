# frozen_string_literal: true

# Raised when a requested correction field/value/transition is not one the
# backend permits -- e.g. correcting `status_code` to `paid` without evidence
# of a real provider success event already on record (never let a correction
# infer provider success; see Admin::Payments::CorrectionService).
class PaymentCorrectionNotAllowedError < BaseError
  def initialize(field: nil, message: nil)
    message ||= I18n.t('api.errors.payment_correction_not_allowed')
    super(code: 'payment_correction_not_allowed', message:, status: :unprocessable_content, field:)
  end
end

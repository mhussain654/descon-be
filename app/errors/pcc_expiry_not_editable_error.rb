# frozen_string_literal: true

class PccExpiryNotEditableError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.pcc_expiry_not_editable')
    super(
      code: 'pcc_expiry_not_editable',
      message:,
      status: :unprocessable_entity,
      field: 'candidate_document.expires_on'
    )
  end
end

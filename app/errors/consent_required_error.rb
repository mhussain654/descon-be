# frozen_string_literal: true

class ConsentRequiredError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.consent_required')
    super(code: 'consent_required', message:, status: :forbidden)
  end
end

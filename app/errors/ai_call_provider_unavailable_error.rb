# frozen_string_literal: true

class AiCallProviderUnavailableError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_provider_unavailable')
    super(code: 'ai_call_provider_unavailable', message:, status: :service_unavailable)
  end
end

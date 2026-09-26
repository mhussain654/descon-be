# frozen_string_literal: true

class AiCallProviderRequestError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_provider_request_failed')
    super(code: 'ai_call_provider_request_failed', message:, status: :bad_gateway)
  end
end

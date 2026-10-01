# frozen_string_literal: true

class AiCallInboundDisabledError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_inbound_disabled')
    super(code: 'ai_call_inbound_disabled', message:, status: :service_unavailable)
  end
end

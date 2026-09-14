# frozen_string_literal: true

class AiCallOutboundDisabledError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_outbound_disabled')
    super(code: 'ai_call_outbound_disabled', message:, status: :service_unavailable)
  end
end

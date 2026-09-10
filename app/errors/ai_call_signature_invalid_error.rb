# frozen_string_literal: true

class AiCallSignatureInvalidError < BaseError
  def initialize(field: 'ai_call_webhook.signature', message: nil)
    message ||= I18n.t('api.errors.ai_call_signature_invalid')
    super(code: 'ai_call_signature_invalid', message:, status: :unauthorized, field:)
  end
end

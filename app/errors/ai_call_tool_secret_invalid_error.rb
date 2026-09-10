# frozen_string_literal: true

class AiCallToolSecretInvalidError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_tool_secret_invalid')
    super(code: 'ai_call_tool_secret_invalid', message:, status: :unauthorized)
  end
end

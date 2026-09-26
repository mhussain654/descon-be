# frozen_string_literal: true

class AiCallToolCallNotAllowedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_tool_call_not_allowed')
    super(code: 'ai_call_tool_call_not_allowed', message:, status: :forbidden)
  end
end

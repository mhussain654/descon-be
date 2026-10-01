# frozen_string_literal: true

class AiCallTriggerCooldownError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_trigger_cooldown')
    super(code: 'ai_call_trigger_cooldown', message:, status: :too_many_requests)
  end
end

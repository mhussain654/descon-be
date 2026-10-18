# frozen_string_literal: true

# A RoboCall call needs a voice id and the chosen trigger has none (for
# example a manual scenario call, or a stage whose script has no voice).
class AiCallVoiceNotConfiguredError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_voice_not_configured')
    super(code: 'ai_call_voice_not_configured', message:, status: :unprocessable_content)
  end
end

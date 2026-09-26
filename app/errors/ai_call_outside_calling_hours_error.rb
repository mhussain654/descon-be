# frozen_string_literal: true

class AiCallOutsideCallingHoursError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_outside_calling_hours')
    super(code: 'ai_call_outside_calling_hours', message:, status: :unprocessable_content)
  end
end

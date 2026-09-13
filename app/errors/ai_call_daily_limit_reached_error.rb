# frozen_string_literal: true

class AiCallDailyLimitReachedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_daily_limit_reached')
    super(code: 'ai_call_daily_limit_reached', message:, status: :too_many_requests)
  end
end

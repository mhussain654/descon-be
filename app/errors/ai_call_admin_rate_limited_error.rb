# frozen_string_literal: true

class AiCallAdminRateLimitedError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_admin_rate_limited')
    super(code: 'ai_call_admin_rate_limited', message:, status: :too_many_requests)
  end
end

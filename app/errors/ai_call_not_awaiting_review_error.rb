# frozen_string_literal: true

class AiCallNotAwaitingReviewError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_not_awaiting_review')
    super(code: 'ai_call_not_awaiting_review', message:, status: :unprocessable_content)
  end
end

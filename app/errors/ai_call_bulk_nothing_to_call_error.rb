# frozen_string_literal: true

# A bulk call was started but no candidate at that stage is left to call with
# that voice (everyone has been called, or has no usable number).
class AiCallBulkNothingToCallError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.ai_call_bulk_nothing_to_call')
    super(code: 'ai_call_bulk_nothing_to_call', message:, status: :unprocessable_content)
  end
end

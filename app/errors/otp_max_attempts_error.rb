# frozen_string_literal: true

# Same non-oracle reasoning as OtpExpiredError -- reachable for a real or a
# decoy challenge alike.
class OtpMaxAttemptsError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.otp_max_attempts')
    super(code: 'otp_max_attempts', message:, status: :unauthorized)
  end
end

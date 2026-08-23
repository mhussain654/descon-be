# frozen_string_literal: true

# Only ever raised once a real, active challenge for a resolvable candidate
# has already been matched by verify -- never reachable for an unknown CNIC
# (see OtpInvalidError), so it does not function as an existence oracle.
class OtpExpiredError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.otp_expired')
    super(code: 'otp_expired', message:, status: :unauthorized)
  end
end

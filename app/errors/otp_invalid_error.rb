# frozen_string_literal: true

# Deliberately the same error for: unknown CNIC, no requested challenge,
# an already-consumed (replayed) challenge, and a wrong code against a real
# active challenge. Distinguishing any of these would let a caller learn
# whether a given CNIC exists or has an in-flight OTP (ticket: "Responses do
# not reveal whether a CNIC exists ... use one generic response shape for
# all non-success identity cases").
class OtpInvalidError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.otp_invalid')
    super(code: 'otp_invalid', message:, status: :unauthorized)
  end
end

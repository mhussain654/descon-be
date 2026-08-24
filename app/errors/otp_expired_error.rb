# frozen_string_literal: true

# Raised once any active challenge -- real or decoy (see
# CandidateOtpChallenge#belongs_to :candidate, optional: true) -- has
# expired. Reachable for both a real candidate and an unknown CNIC that
# previously called /request, so it does not function as an existence
# oracle.
class OtpExpiredError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.otp_expired')
    super(code: 'otp_expired', message:, status: :unauthorized)
  end
end

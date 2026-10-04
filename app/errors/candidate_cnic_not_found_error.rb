# frozen_string_literal: true

# Deliberate exception to the usual "never disclose whether an identifier
# exists" rule (see AGENTS.md's "Security requirements" section, which
# documents this exact client-approved carve-out for the candidate OTP
# request endpoint): this app is reachable only by the client's own
# already-registered candidates, not the public, and many are first-time
# smartphone users who mistype a digit of their own CNIC -- telling them
# plainly beats leaving them stuck on a silent retry loop. The localized
# response uses the approved registration wording and does not echo the CNIC.
class CandidateCnicNotFoundError < BaseError
  def initialize(cnic:, message: nil)
    message ||= I18n.t('api.errors.candidate_cnic_not_found', cnic:)
    super(code: 'candidate_cnic_not_found', message:, status: :not_found)
  end
end

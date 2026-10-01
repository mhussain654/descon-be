# frozen_string_literal: true

# Deliberate exception to the usual "never disclose whether an identifier
# exists" rule (see AGENTS.md's "Security requirements" section, which
# documents this exact client-approved carve-out for the candidate OTP
# request endpoint): this app is reachable only by the client's own
# already-registered candidates, not the public, and many are first-time
# smartphone users who mistype a digit of their own CNIC -- telling them
# plainly, including the value they entered, beats leaving them stuck on a
# silent retry loop with no way to tell a typo from a real system problem.
class CandidateCnicNotFoundError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.candidate_cnic_not_found')
    super(code: 'candidate_cnic_not_found', message:, status: :not_found)
  end
end

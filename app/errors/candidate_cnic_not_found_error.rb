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
  # `cnic` (the normalized value actually looked up, e.g. "42001-1004242-3")
  # is interpolated into the message server-side rather than left for the
  # frontend to append from its own local state -- the frontend's CNIC input
  # is live and keeps changing as the candidate types a correction, so
  # reconstructing "...this CNIC: <value>" client-side from that live state
  # showed whatever was currently *typed*, not what was actually submitted
  # and found missing. Freezing the value into the message at the moment
  # this error is raised fixes that regardless of what the candidate types
  # afterward.
  def initialize(cnic:, message: nil)
    message ||= I18n.t('api.errors.candidate_cnic_not_found', cnic:)
    super(code: 'candidate_cnic_not_found', message:, status: :not_found)
  end
end

# frozen_string_literal: true

# Raised when an update tries to change project/country/craft after the
# candidate has moved past the `registered` stage -- document requirements
# are already resolved from that assignment's project/country/craft
# combination once the candidate advances, so changing them later would
# silently invalidate requirements the candidate may already be uploading
# against.
class CandidateAssignmentFieldLockedError < BaseError
  def initialize(field:)
    super(
      code: 'candidate_assignment_field_locked',
      message: I18n.t('api.errors.candidate_assignment_field_locked'),
      status: :unprocessable_content,
      field:
    )
  end
end

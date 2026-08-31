# frozen_string_literal: true

# Raised when a candidate/assignment update supplies an `expected_updated_at`
# that no longer matches the current record -- the same "someone else changed
# this first" conflict the workflow feature already models via
# `expected_current_stage_code`/WorkflowTransitionStaleError, adapted here
# since a profile edit is a plain attribute update, not a stage transition.
class StaleCandidateError < BaseError
  def initialize
    super(
      code: 'stale_candidate',
      message: I18n.t('api.errors.stale_candidate'),
      status: :conflict
    )
  end
end

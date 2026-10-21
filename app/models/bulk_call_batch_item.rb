# frozen_string_literal: true

# One candidate inside a BulkCallBatch. `queued` until the background job
# places the call (`placed`, linked to its CandidateAiCall), or it could not
# be (`skipped` for a reason the candidate/situation caused, `failed` when the
# provider did). Only `queued` and calls already made keep a candidate out of
# the next batch, so `skipped` and `failed` candidates can be called again.
class BulkCallBatchItem < ApplicationRecord
  STATUSES = %w[queued placed skipped failed].freeze
  SKIP_REASONS = %w[
    stage_changed candidate_inactive no_assignment outside_calling_hours daily_limit_reached calling_disabled
    provider_error
  ].freeze

  belongs_to :bulk_call_batch, inverse_of: :items
  belongs_to :candidate
  belongs_to :candidate_assignment
  belongs_to :candidate_ai_call, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :skip_reason, inclusion: { in: SKIP_REASONS }, allow_nil: true

  scope :queued, -> { where(status: 'queued') }
end

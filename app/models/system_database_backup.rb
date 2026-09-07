# frozen_string_literal: true

# One attempt of the daily database backup job (MPS-903): a gzipped pg_dump
# attached privately via ActiveStorage, with its outcome recorded here so an
# admin can browse and download any day's backup.
#
# Unlike AuditEvent/PaymentEvent, this is *not* an ImmutableRecord: the
# owning job writes it in two phases (created as in_progress before the
# dump even starts, so a crash mid-backup is itself visible as a stalled
# row rather than silence, then updated to succeeded/failed once the dump
# finishes) -- the same queued/processing/completed lifecycle
# CandidateImportBatch already uses for the same reason. "Cannot be edited
# through application APIs" (matching every other audit-style resource in
# this app) is enforced structurally instead: no update/destroy route or
# controller action exists for it at all -- only the job itself, internal
# application code, ever transitions its status.
class SystemDatabaseBackup < ApplicationRecord
  STATUS_CODES = %w[in_progress succeeded failed].freeze

  has_one_attached :archive

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :status_code, presence: true, inclusion: { in: STATUS_CODES }
  validates :taken_at, presence: true

  scope :succeeded, -> { where(status_code: 'succeeded') }

  def succeeded? = status_code == 'succeeded'
  def failed? = status_code == 'failed'

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end

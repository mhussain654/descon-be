# frozen_string_literal: true

# A single bulk CSV import run of candidates, tracking its preflight payload, processing
# status and lifecycle from upload through commit or invalidation.
class CandidateImportBatch < ApplicationRecord
  STATUSES = %w[queued processing completed partial failed invalidated].freeze

  belongs_to :actor, class_name: 'User'
  has_many :row_results, class_name: 'CandidateImportRowResult', dependent: :restrict_with_exception

  encrypts :preflight_payload

  before_validation :assign_public_id, on: :create

  validates :public_id, :token_digest, :source_filename, :file_fingerprint, :template_version, :expires_at,
            presence: true
  validates :public_id, :token_digest, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  # Whether the batch's preflight window has passed and it can no longer be committed.
  def expired? = expires_at <= Time.current
  # Whether the batch has only been preflighted (validated) and not yet committed.
  def preflighted? = queued?
  # Whether the batch is preflighted and awaiting a decision to commit.
  def queued? = status == 'queued'
  # Whether the batch is currently being committed.
  def processing? = status == 'processing'
  # Whether the batch's commit run failed outright.
  def failed? = status == 'failed'
  # Whether the batch was discarded before being committed.
  def invalidated? = status == 'invalidated'
  # Whether the batch finished committing, whether fully or partially.
  def committed? = completed? || partial?
  # Whether every row in the batch was committed successfully.
  def completed? = status == 'completed'
  # Whether some but not all rows in the batch were committed successfully.
  def partial? = status == 'partial'
  # Whether the batch has reached a terminal state (committed or invalidated).
  def finalized? = committed? || invalidated?

  # The parsed rows from the stored preflight payload.
  def rows
    JSON.parse(preflight_payload.to_s).fetch('rows')
  end

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end

# frozen_string_literal: true

# One bulk-call run: up to a fixed number of candidates at a single workflow
# stage, all played the same voice. The candidates are its items.
class BulkCallBatch < ApplicationRecord
  belongs_to :created_by, class_name: 'User'
  belongs_to :robocall_voice

  has_many :items, class_name: 'BulkCallBatchItem', dependent: :restrict_with_exception, inverse_of: :bulk_call_batch

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :provider_voice_id, :voice_name, presence: true
  validates :workflow_stage_code, presence: true,
                                  inclusion: { in: -> { WorkflowStage::CANONICAL_STAGES.map { |s| s.fetch(:code) } } }
  validates :requested_limit, :selected_count, numericality: { only_integer: true, greater_than: 0 }

  # Item counts by status, zero-filled: {'queued' => 3, 'placed' => 10, ...}.
  def status_counts
    counts = items.group(:status).count
    BulkCallBatchItem::STATUSES.index_with { |status| counts.fetch(status, 0) }
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end

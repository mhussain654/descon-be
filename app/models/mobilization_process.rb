# frozen_string_literal: true

# A versioned, ordered mobilization workflow for one destination country (or,
# with no country, the provisional common process used until a country's own
# requirements are confirmed). Candidate assignments are attached to the
# version that was active when they were created and stay on it for
# auditability -- a later version never re-routes an in-flight candidate.
#
# Lifecycle: draft (stages editable) -> active (published, immutable) ->
# retired (still immutable; kept for the assignments already attached).
# Changing a published process means publishing a new version.
class MobilizationProcess < ApplicationRecord
  STATUSES = %w[draft active retired].freeze
  CODE_FORMAT = /\A[a-z0-9_]+\z/
  # Once published, only the lifecycle fields below may change (retiring).
  MUTABLE_AFTER_PUBLISH = %w[status effective_until updated_at].freeze

  belongs_to :country, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :published_by, class_name: 'User', optional: true

  has_many :stages, -> { order(:position) }, class_name: 'MobilizationProcessStage',
                                             inverse_of: :mobilization_process, dependent: :restrict_with_exception
  has_many :candidate_assignments, dependent: :restrict_with_exception

  scope :active, -> { where(status: 'active') }

  validates :code, presence: true, format: { with: CODE_FORMAT }, uniqueness: { scope: :version }
  validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :provisional, inclusion: { in: [true, false] }
  validate :published_definition_is_immutable, on: :update
  validate :retired_cannot_be_reactivated, on: :update

  before_destroy :prevent_published_destroy, prepend: true

  # The process a new assignment for `country` should be attached to: the
  # country's active process, else the active common process. Nil only when
  # neither has been published (seeds always publish the common process).
  def self.resolve_for(country)
    active.find_by(country_id: country&.id) || active.find_by(country_id: nil)
  end

  def published? = status_in_database.present? && status_in_database != 'draft'

  def common? = country_id.nil?

  # Activates this draft, retiring whichever process was active for the same
  # country (or the common slot) in the same transaction, so there is never a
  # moment with two active versions.
  def publish!(by: nil, at: Time.current)
    ensure_publishable!

    transaction do
      self.class.active.where(country_id:).where.not(id:).find_each { |current| current.retire!(at:) }
      update!(status: 'active', published_by: by, published_at: at, effective_from: effective_from || at)
    end
  end

  def ensure_publishable!
    return if status == 'draft' && stages.exists?

    errors.add(:status, :invalid)
    raise ActiveRecord::RecordInvalid, self
  end

  def retire!(at: Time.current)
    update!(status: 'retired', effective_until: at)
  end

  def first_stage = stages.first

  def terminal_stage = stages.last

  # The process stage representing `workflow_stage` in this process, or nil
  # if this process doesn't include that stage at all.
  def stage_for(workflow_stage)
    return if workflow_stage.blank?

    stages.find { |stage| stage.workflow_stage_id == workflow_stage.id }
  end

  def next_stage_after(process_stage)
    return if process_stage.blank?

    stages.find { |stage| stage.position > process_stage.position }
  end

  # The process stage for the catalog stage `code`, or nil if this process
  # doesn't include it (compared by id, so it needs no per-stage catalog load).
  def stage_with_code(code)
    workflow_stage_id = WorkflowStage.where(code:).pick(:id)
    workflow_stage_id && stages.find { |stage| stage.workflow_stage_id == workflow_stage_id }
  end

  def includes_stage_code?(code) = stage_with_code(code).present?

  private

  def published_definition_is_immutable
    return unless published?

    changed_fields = changes_to_save.keys - MUTABLE_AFTER_PUBLISH
    errors.add(:base, :published_process_immutable) if changed_fields.any?
  end

  def retired_cannot_be_reactivated
    return unless status_in_database == 'retired' && status != 'retired'

    errors.add(:status, :invalid)
  end

  def prevent_published_destroy
    return unless published?

    errors.add(:base, :published_process_immutable)
    throw :abort
  end
end

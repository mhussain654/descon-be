# frozen_string_literal: true

# An immutable record of a candidate assignment transitioning from one workflow stage to another.
class CandidateStageHistory < ApplicationRecord
  include ImmutableRecord

  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :candidate_assignment
  belongs_to :from_workflow_stage, class_name: 'WorkflowStage', optional: true
  belongs_to :to_workflow_stage, class_name: 'WorkflowStage'
  belongs_to :actor, class_name: 'User', optional: true
  # Which process version and process stages this transition moved between,
  # plus `stage_code`/`stage_name_*`/`position` as an immutable snapshot of the
  # destination at that moment -- filled in from the assignment's own process
  # on create (optional only for rows that predate processes).
  belongs_to :mobilization_process, optional: true
  belongs_to :from_mobilization_process_stage, class_name: 'MobilizationProcessStage', optional: true
  belongs_to :to_mobilization_process_stage, class_name: 'MobilizationProcessStage', optional: true

  has_many :candidate_workflow_events, dependent: :restrict_with_exception

  before_validation :link_mobilization_process, on: :create

  validates :occurred_at, presence: true
  validates :metadata, exclusion: { in: [nil] }
  validates :reason_code, format: { with: CODE_FORMAT }, allow_blank: true
  validate :transition_stages_are_distinct

  private

  def link_mobilization_process
    process = candidate_assignment&.mobilization_process
    return if process.blank? || to_workflow_stage.blank?

    self.mobilization_process ||= process
    self.from_mobilization_process_stage ||= process.stage_for(from_workflow_stage)
    self.to_mobilization_process_stage ||= process.stage_for(to_workflow_stage)
    snapshot_destination_stage
  end

  # Labels and position as they read right now, kept even if the catalog's
  # names or a later process version change.
  def snapshot_destination_stage
    self.stage_code ||= to_workflow_stage.code
    self.stage_name_en ||= to_workflow_stage.name_for(locale: :en)
    self.stage_name_ur ||= to_workflow_stage.name_for(locale: :ur)
    self.position ||= to_mobilization_process_stage&.position
  end

  # A transition must actually move to a different stage than it came from.
  def transition_stages_are_distinct
    return if from_workflow_stage_id.blank? || from_workflow_stage_id != to_workflow_stage_id

    errors.add(:from_workflow_stage, :invalid)
  end
end

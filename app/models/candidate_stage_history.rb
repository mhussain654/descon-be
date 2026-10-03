# frozen_string_literal: true

# An immutable record of a candidate assignment transitioning from one workflow stage to another.
class CandidateStageHistory < ApplicationRecord
  include ImmutableRecord

  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :candidate_assignment
  belongs_to :from_workflow_stage, class_name: 'WorkflowStage', optional: true
  belongs_to :to_workflow_stage, class_name: 'WorkflowStage'
  belongs_to :actor, class_name: 'User', optional: true
  # Which process version and process stages this transition moved between (filled in from the
  # assignment's own process on create), plus an immutable snapshot of both ends -- code,
  # English/Urdu name and position at transition time -- that history is served from.
  belongs_to :mobilization_process
  belongs_to :from_mobilization_process_stage, class_name: 'MobilizationProcessStage', optional: true
  belongs_to :to_mobilization_process_stage, class_name: 'MobilizationProcessStage'

  has_many :candidate_workflow_events, dependent: :restrict_with_exception

  before_validation :link_mobilization_process, on: :create

  validates :occurred_at, presence: true
  validates :stage_code, :stage_name_en, :stage_name_ur, :position, presence: true
  validates :metadata, exclusion: { in: [nil] }
  validates :reason_code, format: { with: CODE_FORMAT }, allow_blank: true
  validate :transition_stages_are_distinct

  # The destination (`:to`) or origin (`:from`) as recorded at transition time,
  # named in the current locale; nil for the origin of a first entry.
  def snapshot_stage(side)
    prefix = side == :from ? 'from_' : ''
    code = self[:"#{prefix}stage_code"]
    return if code.blank?

    name = I18n.locale.to_s == 'ur' ? self[:"#{prefix}stage_name_ur"] : self[:"#{prefix}stage_name_en"]
    { code:, name:, position: self[:"#{prefix}position"] }.compact
  end

  private

  def link_mobilization_process
    process = candidate_assignment&.mobilization_process
    return if process.blank? || to_workflow_stage.blank?

    self.mobilization_process ||= process
    self.from_mobilization_process_stage ||= process.stage_for(from_workflow_stage)
    self.to_mobilization_process_stage ||= process.stage_for(to_workflow_stage)
    snapshot_stages
  end

  # Labels and positions as they read right now, kept even if the catalog's
  # names or a later process version change.
  def snapshot_stages
    fill_snapshot('', to_workflow_stage, to_mobilization_process_stage)
    fill_snapshot('from_', from_workflow_stage, from_mobilization_process_stage) if from_workflow_stage.present?
  end

  def fill_snapshot(prefix, stage, process_stage)
    {
      stage_code: stage.code, stage_name_en: stage.name_for(locale: :en),
      stage_name_ur: stage.name_for(locale: :ur), position: process_stage&.position
    }.each { |attribute, value| self[:"#{prefix}#{attribute}"] ||= value }
  end

  # A transition must actually move to a different stage than it came from.
  def transition_stages_are_distinct
    return if from_workflow_stage_id.blank? || from_workflow_stage_id != to_workflow_stage_id

    errors.add(:from_workflow_stage, :invalid)
  end
end

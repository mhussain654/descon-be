# frozen_string_literal: true

class CandidateStageHistory < ApplicationRecord
  include ImmutableRecord

  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :candidate_assignment
  belongs_to :from_workflow_stage, class_name: 'WorkflowStage', optional: true
  belongs_to :to_workflow_stage, class_name: 'WorkflowStage'
  belongs_to :actor, class_name: 'User', optional: true

  has_many :candidate_workflow_events, dependent: :restrict_with_exception

  validates :occurred_at, presence: true
  validates :metadata, exclusion: { in: [nil] }
  validates :reason_code, format: { with: CODE_FORMAT }, allow_blank: true
  validate :transition_stages_are_distinct

  private

  def transition_stages_are_distinct
    return if from_workflow_stage_id.blank? || from_workflow_stage_id != to_workflow_stage_id

    errors.add(:from_workflow_stage, :invalid)
  end
end

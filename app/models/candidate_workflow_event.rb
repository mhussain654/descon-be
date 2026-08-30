# frozen_string_literal: true

class CandidateWorkflowEvent < ApplicationRecord
  include ImmutableRecord

  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :candidate
  belongs_to :candidate_assignment
  belongs_to :candidate_stage_history
  belongs_to :actor, class_name: 'User', optional: true

  validates :event_code, presence: true, format: { with: CODE_FORMAT }
  validates :request_id, :occurred_at, presence: true
  validates :payload, exclusion: { in: [nil] }
  validate :assignment_belongs_to_candidate
  validate :history_belongs_to_assignment

  private

  def assignment_belongs_to_candidate
    return if candidate_assignment&.candidate_id == candidate_id

    errors.add(:candidate_assignment, :invalid)
  end

  def history_belongs_to_assignment
    return if candidate_stage_history&.candidate_assignment_id == candidate_assignment_id

    errors.add(:candidate_stage_history, :invalid)
  end
end

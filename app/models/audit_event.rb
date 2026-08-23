# frozen_string_literal: true

class AuditEvent < ApplicationRecord
  include ImmutableRecord

  CODE_FORMAT = /\A[a-z0-9_]+\z/

  belongs_to :candidate, optional: true
  belongs_to :candidate_assignment, optional: true
  belongs_to :actor, class_name: 'User', optional: true

  before_validation :normalize_codes

  validates :entity_type, presence: true
  validates :entity_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :action_code, presence: true, format: { with: CODE_FORMAT }
  validates :reason_code, format: { with: CODE_FORMAT }, allow_blank: true
  validates :occurred_at, presence: true
  validate :candidate_assignment_matches_candidate

  private

  def normalize_codes
    self.action_code = action_code.to_s.strip.downcase
    self.reason_code = reason_code.to_s.strip.downcase.presence
  end

  def candidate_assignment_matches_candidate
    return if candidate_assignment.blank? || candidate.blank?
    return if candidate_assignment.candidate_id == candidate_id

    errors.add(:candidate_assignment, :invalid)
  end
end

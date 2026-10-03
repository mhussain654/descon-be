# frozen_string_literal: true

# One medical outcome (fit or unfit) for a candidate assignment. The first is
# recorded by the transition into the process's medical-outcome stage (linked
# to that stage-history entry); while an unfit candidate is held at that stage,
# staff record later results as re-decisions. The latest result decides whether
# the candidate may move on.
class CandidateMedicalResult < ApplicationRecord
  OUTCOME_CODES = %w[fit unfit].freeze

  belongs_to :candidate_assignment
  belongs_to :candidate_stage_history, optional: true
  belongs_to :recorded_by, class_name: 'User'

  before_validation :assign_public_id, on: :create

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  validates :public_id, presence: true, uniqueness: true
  validates :outcome_code, inclusion: { in: OUTCOME_CODES }
  validates :result_date, presence: true

  def fit? = outcome_code == 'fit'

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end

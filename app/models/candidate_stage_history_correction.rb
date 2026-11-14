# frozen_string_literal: true

# The corrected details for one stage move (e.g. a medical appointment's centre
# or date), set by a developer after the move. CandidateStageHistory is
# append-only, so the corrected values are kept here and laid over the original
# details by CandidateStageHistory#details. A key set to nil clears that detail.
# Each change is also an audit event with the old and new values and the reason.
class CandidateStageHistoryCorrection < ApplicationRecord
  belongs_to :candidate_stage_history
  belongs_to :updated_by, class_name: 'User'

  validates :candidate_stage_history_id, uniqueness: true
  validate :details_is_an_object

  private

  def details_is_an_object
    errors.add(:details, :invalid) unless details.is_a?(Hash)
  end
end

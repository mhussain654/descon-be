# frozen_string_literal: true

# Records the outcome of a candidate assignment's visa application (issued or rejected),
# including the rejection reason when applicable. The first decision comes with the transition
# into the visa stage (linked to that stage-history entry); while a rejected candidate is held
# there, staff record later decisions (re-application/appeal) with no history link. The latest
# decision decides whether the candidate may move on.
class CandidateVisaDecision < ApplicationRecord
  OUTCOME_CODES = %w[issued rejected].freeze
  REJECTION_REASON_CODES = %w[
    document_discrepancy
    medical_issue
    security_clearance
    embassy_rejection
    incomplete_application
    other
  ].freeze

  belongs_to :candidate_assignment
  belongs_to :candidate_stage_history, optional: true
  belongs_to :recorded_by, class_name: 'User'
  has_one_attached :visa_copy

  before_validation :assign_public_id, on: :create

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  validates :public_id, presence: true, uniqueness: true
  validates :outcome_code, inclusion: { in: OUTCOME_CODES }
  validates :decision_date, presence: true
  validates :rejection_reason_code, inclusion: { in: REJECTION_REASON_CODES }, allow_nil: true
  validate :rejection_reason_matches_outcome

  # Whether the visa was issued.
  def issued? = outcome_code == 'issued'

  # Whether the visa was rejected.
  def rejected? = outcome_code == 'rejected'

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # An issued visa must not carry a rejection reason, and a rejected visa must carry one.
  def rejection_reason_matches_outcome
    if issued? && rejection_reason_code.present?
      errors.add(:rejection_reason_code, :present)
    elsif rejected? && rejection_reason_code.blank?
      errors.add(:rejection_reason_code, :blank)
    end
  end
end

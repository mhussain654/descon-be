# frozen_string_literal: true

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
  belongs_to :candidate_stage_history
  belongs_to :recorded_by, class_name: 'User'
  has_one_attached :visa_copy

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :outcome_code, inclusion: { in: OUTCOME_CODES }
  validates :decision_date, presence: true
  validates :rejection_reason_code, inclusion: { in: REJECTION_REASON_CODES }, allow_nil: true
  validate :rejection_reason_matches_outcome

  def issued? = outcome_code == 'issued'

  def rejected? = outcome_code == 'rejected'

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def rejection_reason_matches_outcome
    if issued? && rejection_reason_code.present?
      errors.add(:rejection_reason_code, :present)
    elsif rejected? && rejection_reason_code.blank?
      errors.add(:rejection_reason_code, :blank)
    end
  end
end

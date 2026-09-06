# frozen_string_literal: true

# A single scheduled attempt at a candidate's QVC (medical/security clearance) appointment,
# recording its outcome or no-show status.
class CandidateQvcAttempt < ApplicationRecord
  OUTCOME_CODES = %w[approved re_medical rejected].freeze

  belongs_to :candidate_assignment
  belongs_to :scheduled_by, class_name: 'User'
  belongs_to :outcome_recorded_by, class_name: 'User', optional: true

  before_validation :assign_public_id, on: :create
  before_validation :normalize_outcome_code

  validates :public_id, presence: true, uniqueness: true
  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: {
    scope: :candidate_assignment_id
  }
  validates :appointment_date, presence: true
  validates :outcome_code, inclusion: { in: OUTCOME_CODES }, allow_nil: true
  validates :no_show, inclusion: { in: [true, false] }
  validate :no_show_and_outcome_are_exclusive
  validate :outcome_fields_are_consistent

  scope :ordered, -> { order(:attempt_number, :id) }
  scope :latest_first, -> { order(attempt_number: :desc, id: :desc) }
  scope :open_attempts, -> { where(outcome_recorded_at: nil) }
  scope :no_shows, -> { where(no_show: true) }

  # Whether this attempt has reached a final result, either an outcome or a no-show.
  def completed?
    outcome_code.present? || no_show?
  end

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Trims and lowercases the outcome code, mapping the legacy 're_medical_required' value
  # to the current 're_medical' code.
  def normalize_outcome_code
    normalized = outcome_code.to_s.strip.downcase.presence
    self.outcome_code = 're_medical' if normalized == 're_medical_required'
    self.outcome_code ||= normalized
  end

  # An attempt can't be both a no-show and have a recorded outcome.
  def no_show_and_outcome_are_exclusive
    return unless no_show? && outcome_code.present?

    errors.add(:outcome_code, :invalid)
  end

  # Outcome-recorded-at and outcome-recorded-by must be set exactly when the attempt is completed.
  def outcome_fields_are_consistent
    return if outcome_fields_blank_without_completion?
    return if outcome_fields_complete?

    add_missing_outcome_errors
  end

  # Whether the attempt is still open and none of the outcome-recording fields are set.
  def outcome_fields_blank_without_completion?
    !completed? && outcome_recorded_at.blank? && outcome_recorded_by.blank?
  end

  # Whether the attempt is completed and both outcome-recording fields are set.
  def outcome_fields_complete?
    completed? && outcome_recorded_at.present? && outcome_recorded_by.present?
  end

  # Flags whichever outcome-recording fields are missing once the attempt is completed.
  def add_missing_outcome_errors
    errors.add(:outcome_recorded_at, :blank) if completed? && outcome_recorded_at.blank?
    errors.add(:outcome_recorded_by, :blank) if completed? && outcome_recorded_by.blank?
  end
end

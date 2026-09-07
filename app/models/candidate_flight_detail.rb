# frozen_string_literal: true

# The travel itinerary booked for a candidate's assignment, plus the eventual record of when
# and by whom the candidate was actually mobilized (departed).
class CandidateFlightDetail < ApplicationRecord
  belongs_to :candidate_assignment
  belongs_to :candidate_stage_history
  belongs_to :mobilized_stage_history, class_name: 'CandidateStageHistory', optional: true
  belongs_to :recorded_by, class_name: 'User'
  belongs_to :mobilized_recorded_by, class_name: 'User', optional: true
  has_one_attached :ticket

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :airline, :flight_number, :sector, presence: true
  validates :flight_departure_at, presence: true
  validate :mobilization_fields_are_consistent
  validate :mobilized_on_is_not_before_flight_departure
  validate :core_fields_are_unchanged_once_mobilized, on: :update

  # Whether the candidate has actually departed/been mobilized on this flight.
  def mobilized? = mobilized_on.present?

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Mobilization date, stage history and recorded-by must be set together or not at all.
  def mobilization_fields_are_consistent
    return if mobilization_fields_blank?
    return if mobilization_fields_complete?

    add_missing_mobilization_errors
  end

  # Whether none of the mobilization fields have been set yet.
  def mobilization_fields_blank?
    mobilized_on.blank? && mobilized_stage_history.blank? && mobilized_recorded_by.blank?
  end

  # Whether all of the mobilization fields have been set.
  def mobilization_fields_complete?
    mobilized_on.present? && mobilized_stage_history.present? && mobilized_recorded_by.present?
  end

  # Flags whichever mobilization fields are missing when the mobilization date is set.
  def add_missing_mobilization_errors
    errors.add(:mobilized_stage_history, :blank) if mobilized_on.present? && mobilized_stage_history.blank?
    errors.add(:mobilized_recorded_by, :blank) if mobilized_on.present? && mobilized_recorded_by.blank?
  end

  # The mobilization date can't be earlier than the day the flight was scheduled to depart.
  def mobilized_on_is_not_before_flight_departure
    return if mobilized_on.blank? || flight_departure_at.blank?
    return if mobilized_on >= flight_departure_at.to_date

    errors.add(:mobilized_on, :invalid)
  end

  # Once a candidate has been mobilized, the core flight details can no longer be edited.
  def core_fields_are_unchanged_once_mobilized
    return if mobilized_on_was.blank?
    return unless changed_attribute_names_to_save.intersect?(%w[airline flight_number sector flight_departure_at])

    errors.add(:base, :invalid)
  end
end

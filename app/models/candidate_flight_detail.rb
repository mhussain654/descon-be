# frozen_string_literal: true

# The travel itinerary booked for a candidate's assignment, plus the eventual record of when
# and by whom the candidate was actually mobilized (departed).
class CandidateFlightDetail < ApplicationRecord
  # Flight days and the mobilization date are Pakistan calendar days.
  PAKISTAN_TIME_ZONE = 'Asia/Karachi'
  # The boarding pass can be uploaded from 2 days before the flight's day to
  # 2 days after it (client decision, Nov 2026): boarding passes are issued at
  # check-in, so anything earlier can't be one, and the days after leave time
  # for a candidate who had no signal at the airport.
  BOARDING_PASS_DAYS_BEFORE_DEPARTURE = 2
  BOARDING_PASS_DAYS_AFTER_DEPARTURE = 2

  belongs_to :candidate_assignment
  belongs_to :candidate_stage_history
  belongs_to :mobilized_stage_history, class_name: 'CandidateStageHistory', optional: true
  belongs_to :recorded_by, class_name: 'User'
  belongs_to :mobilized_recorded_by, class_name: 'User', optional: true
  has_one_attached :ticket
  # The candidate's own photo of their boarding pass, uploaded from the app.
  has_one_attached :boarding_pass

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :airline, :flight_number, presence: true
  validates :flight_departure_at, presence: true
  validate :mobilization_fields_are_consistent
  validate :mobilized_on_is_not_before_flight_departure
  validate :mobilized_on_is_not_in_the_future
  validate :core_fields_are_unchanged_once_mobilized, on: :update

  # Whether the candidate has actually departed/been mobilized on this flight.
  def mobilized? = mobilized_on.present?

  # Whether the candidate has uploaded their boarding pass photo.
  def boarding_pass_uploaded? = boarding_pass_uploaded_at.present?

  # Today's date in Pakistan.
  def self.pakistan_today(now = Time.current) = now.in_time_zone(PAKISTAN_TIME_ZONE).to_date

  # The flight's day in Pakistan, whatever time zone it was stored in.
  def departure_date_in_pakistan = flight_departure_at.in_time_zone(PAKISTAN_TIME_ZONE).to_date

  def boarding_pass_upload_opens_on = departure_date_in_pakistan - BOARDING_PASS_DAYS_BEFORE_DEPARTURE
  def boarding_pass_upload_closes_on = departure_date_in_pakistan + BOARDING_PASS_DAYS_AFTER_DEPARTURE

  # `not_yet_open`, `open` or `closed`, for the given Pakistan day.
  def boarding_pass_upload_state(today = self.class.pakistan_today)
    return 'not_yet_open' if today < boarding_pass_upload_opens_on
    return 'closed' if today > boarding_pass_upload_closes_on

    'open'
  end

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

  # Mobilization is recorded once the candidate has flown, so its date can't be later than today in Pakistan.
  def mobilized_on_is_not_in_the_future
    return if mobilized_on.blank? || !mobilized_on_changed?
    return if mobilized_on <= self.class.pakistan_today

    errors.add(:mobilized_on, :invalid)
  end

  # Once a candidate has been mobilized, the core flight details can no longer be edited.
  def core_fields_are_unchanged_once_mobilized
    return if mobilized_on_was.blank?
    return unless changed_attribute_names_to_save.intersect?(%w[airline flight_number sector flight_departure_at])

    errors.add(:base, :invalid)
  end
end

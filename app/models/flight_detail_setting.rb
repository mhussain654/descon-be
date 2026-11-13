# frozen_string_literal: true

# The single admin-editable row holding the default flight details (airline,
# flight number, sector, departure date and time). Staff adding a candidate's
# flight details get these filled in and may change them; what they send is saved
# for that candidate (CandidateFlightDetail and the stage history), so editing the
# defaults never changes a candidate whose flight was already added.
# #current is the only supported way to obtain the row; it starts blank.
class FlightDetailSetting < ApplicationRecord
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  TEXT_MAX_LENGTH = 100

  belongs_to :updated_by, class_name: 'User', optional: true

  before_validation :normalize_values

  validates :singleton_guard, inclusion: { in: [true] }
  validates :airline, :flight_number, :sector, length: { maximum: TEXT_MAX_LENGTH }
  validates :departure_time, format: { with: TIME_FORMAT }, allow_nil: true
  # The departure is one moment: a date without a time (or the reverse) could not be filled in.
  validates :departure_time, presence: true, if: :departure_on?
  validates :departure_on, presence: true, if: :departure_time?

  before_destroy :raise_readonly_record

  # Returns the singleton row, creating it (blank) on first access anywhere.
  # Race-safe: a concurrent first access reads back the winner's row instead.
  def self.current
    first || create!(singleton_guard: true)
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  # The defaults as the flight stage's evidence fields, leaving out any not set.
  # The departure is a local date and time ("2026-11-20T14:30"), the same value
  # the staff form sends when typed by hand.
  def evidence_defaults
    {
      'airline' => airline,
      'flight_reference' => flight_number,
      'sector' => sector,
      'flight_date' => departure_on && departure_time ? "#{departure_on.iso8601}T#{departure_time}" : nil
    }.compact
  end

  private

  def normalize_values
    %i[airline flight_number sector departure_time].each do |attribute|
      self[attribute] = self[attribute].to_s.squish.presence
    end
  end

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is a singleton and cannot be destroyed"
  end
end

# frozen_string_literal: true

# The single admin-editable row holding the default QVC appointment (centre,
# address, date, time). Staff booking a candidate's QVC appointment get these
# filled in and may change them; the values sent with that booking are saved
# on the candidate's QVC attempt, so editing the defaults never changes a
# booking already made. #current is the only supported way to obtain the row;
# it starts blank. Same shape as MedicalAppointmentSetting.
class QvcAppointmentSetting < ApplicationRecord
  TIME_FORMAT = MedicalAppointmentSetting::TIME_FORMAT
  CENTER_NAME_MAX_LENGTH = MedicalAppointmentSetting::CENTER_NAME_MAX_LENGTH
  CENTER_ADDRESS_MAX_LENGTH = MedicalAppointmentSetting::CENTER_ADDRESS_MAX_LENGTH

  belongs_to :updated_by, class_name: 'User', optional: true

  before_validation :normalize_values

  validates :singleton_guard, inclusion: { in: [true] }
  validates :center_name, length: { maximum: CENTER_NAME_MAX_LENGTH }
  validates :center_address, length: { maximum: CENTER_ADDRESS_MAX_LENGTH }
  validates :appointment_time, format: { with: TIME_FORMAT }, allow_nil: true

  before_destroy :raise_readonly_record

  # Returns the singleton row, creating it (blank) on first access anywhere.
  # Race-safe: a concurrent first access reads back the winner's row instead.
  def self.current
    first || create!(singleton_guard: true)
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  private

  def normalize_values
    self.center_name = center_name.to_s.squish.presence
    self.center_address = center_address.to_s.strip.presence
    self.appointment_time = appointment_time.to_s.strip.presence
  end

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is a singleton and cannot be destroyed"
  end
end

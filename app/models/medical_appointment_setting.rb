# frozen_string_literal: true

# The single admin-editable row holding the default medical appointment (centre,
# address, date, time). Staff moving a candidate into a medical appointment stage
# get these filled in and may change them; the values sent with that move are
# saved on the candidate's stage history (see CandidateWorkflows::StageRequirements),
# so editing the defaults never changes a candidate who was already moved.
# #current is the only supported way to obtain the row; it starts blank.
class MedicalAppointmentSetting < ApplicationRecord
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  CENTER_NAME_MAX_LENGTH = 150
  CENTER_ADDRESS_MAX_LENGTH = 500

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

  # The defaults as transition evidence fields, leaving out any not set.
  def evidence_defaults
    {
      'medical_center_name' => center_name,
      'medical_center_address' => center_address,
      'medical_appointment_date' => appointment_on&.iso8601,
      'medical_appointment_time' => appointment_time
    }.compact
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

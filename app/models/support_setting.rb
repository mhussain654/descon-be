# frozen_string_literal: true

# The single admin-editable row holding the support/helpline phone number
# candidates can call from the app's "Help & support" action. Same singleton
# shape as TrainingSetting -- #current is the only supported way to obtain
# the row. Unlike the training link there is no placeholder default: a
# made-up number would put candidates through to the wrong line, so the row
# starts blank and the candidate action stays unavailable until staff set it.
class SupportSetting < ApplicationRecord
  belongs_to :updated_by, class_name: 'User', optional: true

  before_validation :normalize_phone_number

  validates :singleton_guard, inclusion: { in: [true] }
  validates :phone_number, format: { with: Candidate::MOBILE_NUMBER_FORMAT }, allow_nil: true

  before_destroy :raise_readonly_record

  # Returns the singleton row, creating it (blank) on first access anywhere.
  # Race-safe: a concurrent first access loses the unique-index race and
  # simply reads back the winner's row instead.
  def self.current
    first || create!(singleton_guard: true)
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  private

  # Accepts the human-friendly forms staff naturally type ("+92 300 1234567",
  # "0300-1234567") and stores digits with an optional leading "+".
  def normalize_phone_number
    return if phone_number.nil?

    normalized = phone_number.to_s.strip.gsub(/[\s\-()]/, '')
    self.phone_number = normalized.presence
  end

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is a singleton and cannot be destroyed"
  end
end

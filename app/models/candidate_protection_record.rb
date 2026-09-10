# frozen_string_literal: true

# Tracks a candidate assignment's protectorate appearance and readiness-to-fly milestones,
# each recorded with who logged it and when.
class CandidateProtectionRecord < ApplicationRecord
  belongs_to :candidate_assignment
  belongs_to :appeared_recorded_by, class_name: 'User', optional: true
  belongs_to :ready_recorded_by, class_name: 'User', optional: true

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validate :appearance_fields_are_consistent
  validate :ready_fields_are_consistent
  validate :ready_requires_appearance

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Appearance date, recorded-at and recorded-by must be set together or not at all.
  def appearance_fields_are_consistent
    return if appearance_fields_blank?
    return if appearance_fields_complete?

    add_missing_appearance_errors
  end

  # Ready-to-fly date, recorded-at and recorded-by must be set together or not at all.
  def ready_fields_are_consistent
    return if ready_fields_blank?
    return if ready_fields_complete?

    add_missing_ready_errors
  end

  # A candidate can't be marked as protected/ready-to-fly before they've appeared.
  def ready_requires_appearance
    return unless protected_on.present? && appeared_on.blank?

    errors.add(:protected_on, :invalid)
  end

  # Whether none of the appearance fields have been set yet.
  def appearance_fields_blank?
    appeared_on.blank? && appeared_recorded_at.blank? && appeared_recorded_by.blank?
  end

  # Whether all of the appearance fields have been set.
  def appearance_fields_complete?
    appeared_on.present? && appeared_recorded_at.present? && appeared_recorded_by.present?
  end

  # Flags whichever appearance fields are missing when the appearance date is set.
  def add_missing_appearance_errors
    errors.add(:appeared_recorded_at, :blank) if appeared_on.present? && appeared_recorded_at.blank?
    errors.add(:appeared_recorded_by, :blank) if appeared_on.present? && appeared_recorded_by.blank?
  end

  # Whether none of the readiness fields have been set yet.
  def ready_fields_blank?
    protected_on.blank? && ready_to_fly_at.blank? && ready_recorded_by.blank?
  end

  # Whether all of the readiness fields have been set.
  def ready_fields_complete?
    protected_on.present? && ready_to_fly_at.present? && ready_recorded_by.present?
  end

  # Flags whichever readiness fields are missing when the protected-on date is set.
  def add_missing_ready_errors
    errors.add(:ready_to_fly_at, :blank) if protected_on.present? && ready_to_fly_at.blank?
    errors.add(:ready_recorded_by, :blank) if protected_on.present? && ready_recorded_by.blank?
  end
end

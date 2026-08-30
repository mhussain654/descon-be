# frozen_string_literal: true

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

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def appearance_fields_are_consistent
    return if appeared_on.blank? && appeared_recorded_at.blank? && appeared_recorded_by.blank?
    return if appeared_on.present? && appeared_recorded_at.present? && appeared_recorded_by.present?

    errors.add(:appeared_recorded_at, :blank) if appeared_on.present? && appeared_recorded_at.blank?
    errors.add(:appeared_recorded_by, :blank) if appeared_on.present? && appeared_recorded_by.blank?
  end

  def ready_fields_are_consistent
    return if protected_on.blank? && ready_to_fly_at.blank? && ready_recorded_by.blank?
    return if protected_on.present? && ready_to_fly_at.present? && ready_recorded_by.present?

    errors.add(:ready_to_fly_at, :blank) if protected_on.present? && ready_to_fly_at.blank?
    errors.add(:ready_recorded_by, :blank) if protected_on.present? && ready_recorded_by.blank?
  end

  def ready_requires_appearance
    return unless protected_on.present? && appeared_on.blank?

    errors.add(:protected_on, :invalid)
  end
end

# frozen_string_literal: true

class CandidateDocument < ApplicationRecord
  STATUS_CODES = %w[uploaded under_verification verified rejected].freeze

  belongs_to :candidate_assignment
  belongs_to :document_type
  belongs_to :uploaded_by, class_name: 'User', optional: true
  belongs_to :verified_by, class_name: 'User', optional: true

  before_validation :normalize_status_code
  before_validation :normalize_checksum

  validates :status_code, presence: true, inclusion: { in: STATUS_CODES }
  validates :uploaded_at, presence: true
  validate :verification_fields_are_paired

  private

  def normalize_status_code
    self.status_code = status_code.to_s.strip.downcase
  end

  def normalize_checksum
    self.checksum_sha256 = checksum_sha256.to_s.strip.downcase.presence
  end

  def verification_fields_are_paired
    return if verification_fields_paired?

    errors.add(:verified_by, :blank) if verified_by_id.blank?
    errors.add(:verified_at, :blank) if verified_at.blank?
  end

  def verification_fields_paired?
    verified_by_id.present? == verified_at.present?
  end
end

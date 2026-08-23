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
  validate :status_consistency

  private

  def normalize_status_code
    self.status_code = status_code.to_s.strip.downcase
  end

  def normalize_checksum
    self.checksum_sha256 = checksum_sha256.to_s.strip.downcase.presence
  end

  def status_consistency
    case status_code
    when 'uploaded', 'under_verification'
      require_unreviewed_state
    when 'verified'
      require_verified_state
    when 'rejected'
      require_rejected_state
    end
  end

  def require_present(attribute, value)
    errors.add(attribute, :blank) if value.blank?
  end

  def require_absent(attribute, value)
    errors.add(attribute, :present) if value.present?
  end

  def require_unreviewed_state
    require_absent(:verified_by, verified_by_id)
    require_absent(:verified_at, verified_at)
    require_absent(:rejection_reason, rejection_reason)
  end

  def require_verified_state
    require_present(:verified_by, verified_by_id)
    require_present(:verified_at, verified_at)
    require_absent(:rejection_reason, rejection_reason)
  end

  def require_rejected_state
    require_present(:verified_by, verified_by_id)
    require_present(:verified_at, verified_at)
    require_present(:rejection_reason, rejection_reason)
  end
end

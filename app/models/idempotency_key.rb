# frozen_string_literal: true

class IdempotencyKey < ApplicationRecord
  PROCESSING_STATUS = 'processing'
  COMPLETED_STATUS = 'completed'
  STATUSES = [PROCESSING_STATUS, COMPLETED_STATUS].freeze

  belongs_to :subject, polymorphic: true, optional: true

  validates :idempotency_scope, :key_digest, :request_fingerprint, :request_method, :request_path, :expires_at,
            presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :validate_response_consistency

  scope :active, -> { where('expires_at > ?', Time.current) }

  def processing?
    status == PROCESSING_STATUS
  end

  def completed?
    status == COMPLETED_STATUS
  end

  def expired?
    expires_at <= Time.current
  end

  private

  def validate_response_consistency
    return if processing_state_valid?
    return if completed_state_valid?

    errors.add(:base, :invalid)
  end

  def processing_state_valid?
    processing? && response_status.blank? && response_payload.blank? && completed_at.blank?
  end

  def completed_state_valid?
    completed? && response_status.present? && response_payload.present? && completed_at.present?
  end
end

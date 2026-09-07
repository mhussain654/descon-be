# frozen_string_literal: true

# Records a request's idempotency key so a retried or duplicated write request (e.g. from a
# flaky mobile connection) can be safely deduplicated and replayed with the original response
# instead of being processed twice.
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

  # True if the original request is still being handled and no response has been recorded yet.
  def processing?
    status == PROCESSING_STATUS
  end

  # True if the original request finished and its response has been recorded for replay.
  def completed?
    status == COMPLETED_STATUS
  end

  # True if this idempotency key has passed its expiry time and should no longer be reused.
  def expired?
    expires_at <= Time.current
  end

  private

  # Ensures the recorded response fields match whichever status (processing or completed) is set.
  def validate_response_consistency
    return if processing_state_valid?
    return if completed_state_valid?

    errors.add(:base, :invalid)
  end

  # True if a "processing" record correctly has no response data recorded yet.
  def processing_state_valid?
    processing? && response_status.blank? && response_payload.blank? && completed_at.blank?
  end

  # True if a "completed" record correctly has its response status, payload, and completion time set.
  def completed_state_valid?
    completed? && response_status.present? && response_payload.present? && completed_at.present?
  end
end

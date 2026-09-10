# frozen_string_literal: true

# An immutable audit log entry recording something that happened to a payment (e.g. a provider
# webhook callback or a manual status change), including who/what triggered it and the raw payload.
class PaymentEvent < ApplicationRecord
  include ImmutableRecord

  CODE_FORMAT = /\A[a-z0-9_]+\z/
  NORMALIZED_CODE_ATTRIBUTES = %i[provider_code event_source event_type].freeze
  STRIPPED_STRING_ATTRIBUTES = %i[event_key provider_order_id provider_transaction_id provider_status_code].freeze

  belongs_to :payment
  belongs_to :candidate_assignment
  belongs_to :actor, class_name: 'User', optional: true

  before_validation :normalize_codes

  validates :provider_code, :event_source, :event_type, :event_key, :occurred_at, presence: true
  validates :provider_code, :event_source, :event_type, format: { with: CODE_FORMAT }
  validates :payload, exclusion: { in: [nil] }
  validate :payment_belongs_to_assignment

  private

  # Callback: strips and downcases the provider/source/type code attributes, and strips the
  # remaining provider reference string attributes, before validation.
  def normalize_codes
    NORMALIZED_CODE_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.downcase.presence
    end

    STRIPPED_STRING_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.presence
    end
  end

  # Ensures this event's candidate assignment matches the assignment on its associated payment.
  def payment_belongs_to_assignment
    return if payment.blank? || candidate_assignment.blank?
    return if payment.candidate_assignment_id == candidate_assignment_id

    errors.add(:candidate_assignment, :invalid)
  end
end

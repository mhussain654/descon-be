# frozen_string_literal: true

# An immutable log entry recording one thing that happened on an AI voice
# call (a provider webhook, a tool call, a reconciliation-job finding, or an
# admin's manual review action), mirroring PaymentEvent exactly. The unique
# index on (provider_code, event_key) is this table's second job: a
# duplicate webhook/tool-call delivery finds its existing row instead of
# inserting a new one, which is how webhook idempotency is enforced (see
# AiCalls::WebhookEventRecorder) -- there is no separate idempotency table.
class CandidateAiCallEvent < ApplicationRecord
  include ImmutableRecord

  CODE_FORMAT = /\A[a-z0-9_]+\z/
  NORMALIZED_CODE_ATTRIBUTES = %i[provider_code event_source event_type].freeze
  STRIPPED_STRING_ATTRIBUTES = %i[event_key request_id].freeze

  belongs_to :candidate_ai_call
  belongs_to :actor, class_name: 'User', optional: true

  before_validation :normalize_codes

  validates :provider_code, :event_source, :event_type, :event_key, :occurred_at, presence: true
  validates :provider_code, :event_source, :event_type, format: { with: CODE_FORMAT }
  validates :payload, exclusion: { in: [nil] }

  private

  # Strips and downcases the provider/source/type code attributes, and strips
  # the remaining string attributes, before validation.
  def normalize_codes
    NORMALIZED_CODE_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.downcase.presence
    end

    STRIPPED_STRING_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.presence
    end
  end
end

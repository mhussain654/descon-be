# frozen_string_literal: true

# The header/lifecycle row for one AI voice call (ElevenLabs + Twilio),
# outbound (admin-triggered) or inbound (candidate helpline). Genuinely
# mutable -- a call progresses through `status` as it happens and `outcome`
# is resolved once known (a call can be `completed` while its `outcome` is
# still `callback_required`, so the two are tracked independently rather
# than collapsed into one field). Everything that *happened* on the call is
# recorded immutably on CandidateAiCallEvent; this row is the current state,
# not the history.
class CandidateAiCall < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/
  DIRECTIONS = %w[inbound outbound].freeze
  STATUSES = %w[requested queued ringing in_progress processing completed failed cancelled].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled].freeze
  OUTCOMES = %w[answered not_answered callback_required].freeze
  VERIFICATION_STATUSES = %w[not_applicable pending verified failed skipped].freeze
  LANGUAGES = %w[en ur].freeze
  NORMALIZED_CODE_ATTRIBUTES = %i[
    direction call_reason status outcome outcome_reason provider_code failure_code verification_status
  ].freeze

  belongs_to :communication
  belongs_to :candidate, optional: true
  belongs_to :candidate_assignment, optional: true
  belongs_to :triggered_by, class_name: 'User', optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true

  has_many :candidate_ai_call_events, dependent: :restrict_with_exception
  has_one :candidate_ai_call_transcript, dependent: :restrict_with_exception

  before_validation :assign_public_id, on: :create
  before_validation :normalize_codes

  validates :public_id, presence: true, uniqueness: true
  validates :direction, presence: true, inclusion: { in: DIRECTIONS }
  validates :call_reason, presence: true, format: { with: CODE_FORMAT }
  validates :language_code, inclusion: { in: LANGUAGES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
  validates :outcome_reason, format: { with: CODE_FORMAT }, allow_blank: true
  validates :provider_code, presence: true, format: { with: CODE_FORMAT }
  validates :failure_code, format: { with: CODE_FORMAT }, allow_blank: true
  validates :verification_status, presence: true, inclusion: { in: VERIFICATION_STATUSES }
  validates :verification_attempts, numericality: { greater_than_or_equal_to: 0 }
  validates :extracted_data, exclusion: { in: [nil] }
  validate :candidate_assignment_matches_candidate

  scope :outbound, -> { where(direction: 'outbound') }
  scope :inbound, -> { where(direction: 'inbound') }
  scope :in_status, ->(status) { where(status:) }
  scope :awaiting_review, -> { where(outcome_reason: 'needs_manual_review', reviewed_at: nil) }
  scope :non_terminal, -> { where.not(status: TERMINAL_STATUSES) }

  # True once ElevenLabs/Twilio have finished with this call -- the call
  # itself is over, independent of whether its business `outcome` is known.
  def terminal_status? = status.in?(TERMINAL_STATUSES)

  def needs_manual_review? = outcome.nil? && outcome_reason == 'needs_manual_review'

  private

  # Assigns a public-facing UUID identifier when the call is first created.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Trims and lowercases every code-like attribute before validation.
  def normalize_codes
    NORMALIZED_CODE_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.downcase.presence
    end

    self.status ||= 'requested'
    self.provider_code = provider_code.presence || 'elevenlabs'
    self.verification_status ||= 'not_applicable'
  end

  # Ensures that when both are set, the linked assignment actually belongs to the linked candidate
  # (mirrors AuditEvent#candidate_assignment_matches_candidate).
  def candidate_assignment_matches_candidate
    return if candidate_assignment.blank? || candidate.blank?
    return if candidate_assignment.candidate_id == candidate_id

    errors.add(:candidate_assignment, :invalid)
  end
end

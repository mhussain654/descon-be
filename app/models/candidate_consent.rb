# frozen_string_literal: true

# A candidate's immutable acknowledgment of a specific policy version, captured with a
# timestamp and the originating IP address as evidence (MPS-204). A candidate accumulates
# one row per policy version they've accepted; only the current version's row matters for
# gating access, but older rows are kept as reportable history.
class CandidateConsent < ApplicationRecord
  include ImmutableRecord

  CURRENT_POLICY_VERSION = '2026-09-06'

  belongs_to :candidate

  before_validation :assign_public_id, on: :create
  before_validation :normalize_policy_version

  validates :public_id, presence: true, uniqueness: true
  validates :policy_version, presence: true
  validates :accepted_at, presence: true
  validates :candidate_id, uniqueness: { scope: :policy_version }

  scope :for_current_policy, -> { where(policy_version: CURRENT_POLICY_VERSION) }

  # Whether this candidate has already accepted the currently-required policy version.
  def self.current_policy_accepted?(candidate)
    for_current_policy.exists?(candidate:)
  end

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Trims the policy version identifier before validation.
  def normalize_policy_version
    self.policy_version = policy_version.to_s.strip
  end
end

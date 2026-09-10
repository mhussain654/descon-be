# frozen_string_literal: true

# Mirrors Session (staff) exactly -- see the migration comment for why
# candidates get a parallel, structurally separate token/session system
# rather than sharing the staff one.
class CandidateSession < ApplicationRecord
  belongs_to :candidate
  has_many :candidate_refresh_tokens, dependent: :destroy

  scope :active, -> { where(revoked_at: nil) }

  before_validation :assign_identifiers, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :jti, presence: true, uniqueness: true

  # Revokes the session and all of its still-active refresh tokens in one transaction.
  def revoke!
    transaction do
      update!(revoked_at: Time.current)
      # rubocop:disable Rails/SkipsModelValidations
      candidate_refresh_tokens.active.update_all(revoked_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  # Whether the session has been revoked.
  def revoked?
    revoked_at.present?
  end

  # Updates the last-seen timestamp, but only if more than 5 minutes have passed since the
  # last update, to avoid writing to the row on every request.
  def touch_last_seen!
    return if last_seen_at&.after?(5.minutes.ago)

    # rubocop:disable Rails/SkipsModelValidations
    update_column(:last_seen_at, Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  # Assigns public-facing UUID identifiers (public_id and JWT ID) on creation, if not already set.
  def assign_identifiers
    self.public_id ||= SecureRandom.uuid
    self.jti ||= SecureRandom.uuid
  end
end

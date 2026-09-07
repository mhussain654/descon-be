# frozen_string_literal: true

# A single login session for a user, identified by a public id and a JWT id (jti), owning the
# refresh tokens issued under it. Can be revoked to log the user out everywhere for that session.
class Session < ApplicationRecord
  belongs_to :user
  has_many :refresh_tokens, dependent: :destroy

  scope :active, -> { where(revoked_at: nil) }

  before_validation :assign_identifiers, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :jti, presence: true, uniqueness: true

  # Ends this session: marks it revoked and revokes all of its still-active refresh tokens.
  def revoke!
    transaction do
      return self if revoked?

      update!(revoked_at: Time.current)
      # Revoking a session should be a single SQL update to avoid per-token callbacks and races.
      # rubocop:disable Rails/SkipsModelValidations
      refresh_tokens.active.update_all(revoked_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  # True if the session has been revoked (logged out).
  def revoked?
    revoked_at.present?
  end

  # Updates the last-seen timestamp, but only if more than 5 minutes have passed since the last
  # update, to avoid writing to the database on every single request.
  def touch_last_seen!
    return if last_seen_at&.after?(5.minutes.ago)

    # This timestamp is operational metadata and does not need full validation overhead.
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:last_seen_at, Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  # Callback: assigns a public-facing UUID and a JWT id (jti) when the session is first created.
  def assign_identifiers
    self.public_id ||= SecureRandom.uuid
    self.jti ||= SecureRandom.uuid
  end
end

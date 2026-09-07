# frozen_string_literal: true

# A single refresh token issued as part of a user session, used to obtain new access tokens.
# Tokens are rotated on use (linked via `replacement`) and can be revoked to end a session early.
class RefreshToken < ApplicationRecord
  EXPIRY_WINDOW = 30.days

  belongs_to :session, inverse_of: :refresh_tokens
  belongs_to :replacement,
             class_name: 'RefreshToken',
             foreign_key: :replaced_by_id,
             inverse_of: false,
             optional: true

  scope :active, -> { where(revoked_at: nil, rotated_at: nil).where('expires_at > ?', Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # True if the token can still be used: not revoked, not rotated away, and not expired.
  def active?
    !revoked? && !rotated? && !expired?
  end

  # True if the token has been explicitly revoked (e.g. on logout or reuse detection).
  def revoked?
    revoked_at.present?
  end

  # True if the token has already been exchanged for a newer one (rotated out of use).
  def rotated?
    rotated_at.present?
  end

  # True if the token's expiry timestamp has passed.
  def expired?
    expires_at.past?
  end
end

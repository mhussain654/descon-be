# frozen_string_literal: true

# Mirrors RefreshToken (staff) exactly -- digest-at-rest, rotation and reuse
# detection are handled identically by CandidateAuthentication::RefreshService.
class CandidateRefreshToken < ApplicationRecord
  EXPIRY_WINDOW = ENV.fetch('CANDIDATE_REFRESH_TOKEN_EXPIRY_DAYS', 30).to_i.days

  belongs_to :candidate_session, inverse_of: :candidate_refresh_tokens
  belongs_to :replacement,
             class_name: 'CandidateRefreshToken',
             foreign_key: :replaced_by_id,
             inverse_of: false,
             optional: true

  scope :active, -> { where(revoked_at: nil, rotated_at: nil).where('expires_at > ?', Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # Whether this token can still be used to obtain a new access token.
  def active?
    !revoked? && !rotated? && !expired?
  end

  # Whether the token was explicitly revoked (e.g. on logout or reuse detection).
  def revoked?
    revoked_at.present?
  end

  # Whether the token has already been exchanged for a replacement token.
  def rotated?
    rotated_at.present?
  end

  # Whether the token's expiry window has passed.
  def expired?
    expires_at.past?
  end
end

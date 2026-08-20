# frozen_string_literal: true

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

  def active?
    !revoked? && !rotated? && !expired?
  end

  def revoked?
    revoked_at.present?
  end

  def rotated?
    rotated_at.present?
  end

  def expired?
    expires_at.past?
  end
end

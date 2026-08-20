# frozen_string_literal: true

class RefreshToken < ApplicationRecord
  EXPIRY_WINDOW = 30.days

  belongs_to :session

  scope :active, -> { where(revoked_at: nil, rotated_at: nil).where('expires_at > ?', Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def active?
    revoked_at.nil? && rotated_at.nil? && expires_at.future?
  end
end

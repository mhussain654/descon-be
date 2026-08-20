# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user
  has_many :refresh_tokens, dependent: :destroy

  scope :active, -> { where(revoked_at: nil) }

  before_validation :assign_identifiers, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :jti, presence: true, uniqueness: true

  def revoke!
    transaction do
      update!(revoked_at: Time.current)
      refresh_tokens.active.find_each { |refresh_token| refresh_token.update!(revoked_at: Time.current) }
    end
  end

  def revoked?
    revoked_at.present?
  end

  def touch_last_seen!
    update!(last_seen_at: Time.current)
  end

  private

  def assign_identifiers
    self.public_id ||= SecureRandom.uuid
    self.jti ||= SecureRandom.uuid
  end
end

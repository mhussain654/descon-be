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
      return self if revoked?

      update!(revoked_at: Time.current)
      # Revoking a session should be a single SQL update to avoid per-token callbacks and races.
      # rubocop:disable Rails/SkipsModelValidations
      refresh_tokens.active.update_all(revoked_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def revoked?
    revoked_at.present?
  end

  def touch_last_seen!
    return if last_seen_at&.after?(5.minutes.ago)

    # This timestamp is operational metadata and does not need full validation overhead.
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:last_seen_at, Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  def assign_identifiers
    self.public_id ||= SecureRandom.uuid
    self.jti ||= SecureRandom.uuid
  end
end

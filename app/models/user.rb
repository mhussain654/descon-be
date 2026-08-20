# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :lockable, :validatable

  has_many :sessions, dependent: :destroy

  enum :role, { member: 'member', admin: 'admin' }, default: :member, validate: true

  before_validation :assign_public_id, on: :create
  before_validation :normalize_email

  validates :active, inclusion: { in: [true, false] }
  validates :public_id, presence: true, uniqueness: true

  def active_for_authentication?
    super && active?
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end

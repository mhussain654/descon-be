# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  has_many :sessions, dependent: :destroy

  enum :role, { member: 'member', admin: 'admin' }, default: :member, validate: true

  before_validation :assign_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end

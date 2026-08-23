# frozen_string_literal: true

class Role < ApplicationRecord
  include HasLocalizedName

  SYSTEM_ROLES = [
    { code: 'admin' },
    { code: 'staff' }
  ].freeze

  has_many :users, primary_key: :code, foreign_key: :role, inverse_of: :staff_role,
                   dependent: :restrict_with_exception
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :active, :system_defined, inclusion: { in: [true, false] }

  def self.i18n_name_scope
    'reference_data.roles'
  end
end

# frozen_string_literal: true

class Role < ApplicationRecord
  include HasLocalizedName

  SYSTEM_ROLES = [
    { code: 'admin' },
    { code: 'hr' },
    { code: 'mps' },
    { code: 'finance' },
    { code: 'management' }
  ].freeze

  has_many :users, primary_key: :code, foreign_key: :role, inverse_of: :staff_role,
                   dependent: :restrict_with_exception
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :active, :system_defined, inclusion: { in: [true, false] }
  validate :protect_system_definition_changes, on: :update

  before_destroy :prevent_system_destroy

  def self.i18n_name_scope
    'reference_data.roles'
  end

  private

  def prevent_system_destroy
    return unless system_defined_in_database

    errors.add(:base, :invalid)
    throw :abort
  end

  def protect_system_definition_changes
    return unless system_defined_in_database

    restricted_fields = %w[code system_defined]
    return unless changes_to_save.keys.intersect?(restricted_fields)

    errors.add(:base, :invalid)
  end
end

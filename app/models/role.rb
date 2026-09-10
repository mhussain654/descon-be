# frozen_string_literal: true

# A staff role (e.g. admin, hr, mps, finance, management) that grants a bundle of permissions
# to the users assigned to it. System-defined roles are seeded and protected from being renamed
# or deleted.
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

  # The I18n key prefix under which this model's translated names are looked up.
  def self.i18n_name_scope
    'reference_data.roles'
  end

  private

  # Callback: blocks deletion of any role that is marked as system-defined in the database.
  def prevent_system_destroy
    return unless system_defined_in_database

    errors.add(:base, :invalid)
    throw :abort
  end

  # Blocks changes to the code or system_defined flag on a role that is system-defined.
  def protect_system_definition_changes
    return unless system_defined_in_database

    restricted_fields = %w[code system_defined]
    return unless changes_to_save.keys.intersect?(restricted_fields)

    errors.add(:base, :invalid)
  end
end

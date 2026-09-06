# frozen_string_literal: true

# A single granular access right (e.g. manage_candidates, view_payments) that can be granted
# to staff roles. System-defined permissions are seeded and protected from being renamed or deleted.
class Permission < ApplicationRecord
  include HasLocalizedName

  SYSTEM_PERMISSIONS = [
    { code: 'manage_staff_users' },
    { code: 'manage_roles_permissions' },
    { code: 'manage_candidates' },
    { code: 'manage_candidate_assignments' },
    { code: 'manage_candidate_documents' },
    { code: 'manage_workflow' },
    { code: 'manage_payments' },
    { code: 'manage_communications' },
    { code: 'view_candidates' },
    { code: 'view_candidate_assignments' },
    { code: 'view_candidate_documents' },
    { code: 'view_workflow' },
    { code: 'view_payments' },
    { code: 'view_communications' },
    { code: 'view_audit_events' },
    { code: 'view_admin_dashboard' },
    { code: 'view_mps_dashboard' },
    { code: 'view_management_dashboard' },
    { code: 'view_reports' }
  ].freeze

  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :active, :system_defined, inclusion: { in: [true, false] }
  validate :protect_system_definition_changes, on: :update

  before_destroy :prevent_system_destroy

  # The I18n key prefix under which this model's translated names are looked up.
  def self.i18n_name_scope
    'reference_data.permissions'
  end

  private

  # Callback: blocks deletion of any permission that is marked as system-defined in the database.
  def prevent_system_destroy
    return unless system_defined_in_database

    errors.add(:base, :invalid)
    throw :abort
  end

  # Blocks changes to the code or system_defined flag on a permission that is system-defined.
  def protect_system_definition_changes
    return unless system_defined_in_database

    restricted_fields = %w[code system_defined]
    return unless changes_to_save.keys.intersect?(restricted_fields)

    errors.add(:base, :invalid)
  end
end

# frozen_string_literal: true

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
    { code: 'view_audit_events' }
  ].freeze

  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :active, :system_defined, inclusion: { in: [true, false] }
  validate :protect_system_definition_changes, on: :update

  before_destroy :prevent_system_destroy

  def self.i18n_name_scope
    'reference_data.permissions'
  end

  private

  def prevent_system_destroy
    return unless system_defined?

    errors.add(:base, :invalid)
    throw :abort
  end

  def protect_system_definition_changes
    return unless system_defined?
    return unless changes_to_save.key?('code')

    errors.add(:base, :invalid)
  end
end

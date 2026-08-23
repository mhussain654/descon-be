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
    { code: 'view_audit_events' }
  ].freeze

  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :active, :system_defined, inclusion: { in: [true, false] }

  def self.i18n_name_scope
    'reference_data.permissions'
  end
end

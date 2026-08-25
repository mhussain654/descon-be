# frozen_string_literal: true

module StaffAuthorizationReferenceData
  ROLE_PERMISSION_MAP = {
    'admin' => Permission::SYSTEM_PERMISSIONS.map { |permission| permission.fetch(:code) },
    'hr' => %w[
      manage_candidates
      manage_candidate_documents
      manage_communications
      view_candidate_assignments
      view_workflow
    ],
    'mps' => %w[
      view_candidates
      manage_candidate_assignments
      manage_candidate_documents
      manage_workflow
      manage_communications
    ],
    'finance' => %w[
      view_candidates
      view_candidate_assignments
      view_candidate_documents
      view_workflow
      manage_payments
    ],
    'management' => %w[
      view_candidates
      view_candidate_assignments
      view_candidate_documents
      view_workflow
      view_payments
      view_communications
      view_audit_events
    ]
  }.freeze

  def ensure_staff_authorization_reference_data!
    ensure_system_roles!
    ensure_system_permissions!
    ensure_role_permissions!
  end

  private

  def ensure_system_roles!
    Role::SYSTEM_ROLES.each do |attributes|
      Role.find_or_create_by!(code: attributes.fetch(:code)) do |role|
        role.system_defined = true
        role.active = true
      end
    end
  end

  def ensure_system_permissions!
    Permission::SYSTEM_PERMISSIONS.each do |attributes|
      Permission.find_or_create_by!(code: attributes.fetch(:code)) do |permission|
        permission.system_defined = true
        permission.active = true
      end
    end
  end

  def ensure_role_permissions!
    ROLE_PERMISSION_MAP.each do |role_code, permission_codes|
      role = Role.find_by!(code: role_code)
      permission_codes.each { |permission_code| ensure_role_permission!(role, permission_code) }
    end
  end

  def ensure_role_permission!(role, permission_code)
    permission = Permission.find_by!(code: permission_code)
    RolePermission.find_or_create_by!(role:, permission:)
  end
end

RSpec.configure do |config|
  config.include StaffAuthorizationReferenceData
end

# frozen_string_literal: true

Role::SYSTEM_ROLES.each do |role_attributes|
  role = Role.find_or_initialize_by(code: role_attributes.fetch(:code))
  role.assign_attributes(system_defined: true, active: true)
  role.save!
end

Permission::SYSTEM_PERMISSIONS.each do |permission_attributes|
  permission = Permission.find_or_initialize_by(code: permission_attributes.fetch(:code))
  permission.assign_attributes(system_defined: true, active: true)
  permission.save!
end

role_ids_by_code = Role.pluck(:code, :id).to_h
permission_ids_by_code = Permission.pluck(:code, :id).to_h

{
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
}.each do |role_code, permission_codes|
  permission_codes.each do |permission_code|
    RolePermission.find_or_create_by!(
      role_id: role_ids_by_code.fetch(role_code),
      permission_id: permission_ids_by_code.fetch(permission_code)
    )
  end
end

WorkflowStage::CANONICAL_STAGES.each do |stage_attributes|
  stage = WorkflowStage.find_or_initialize_by(code: stage_attributes.fetch(:code))
  stage.assign_attributes(
    position: stage_attributes.fetch(:position),
    system_defined: true,
    active: true
  )
  stage.save!
end

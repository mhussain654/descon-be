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

# --- Reference catalogs (MPS-106) -------------------------------------------

[
  { code: 'qatar', name_en: 'Qatar', name_ur: 'قطر' },
  { code: 'saudi_arabia', name_en: 'Saudi Arabia', name_ur: 'سعودی عرب' },
  { code: 'uae', name_en: 'United Arab Emirates', name_ur: 'متحدہ عرب امارات' }
].each do |attributes|
  country = Country.find_or_initialize_by(code: attributes.fetch(:code))
  country.assign_attributes(name_en: attributes.fetch(:name_en), name_ur: attributes.fetch(:name_ur), active: true)
  country.save!
end

[
  { code: 'qatar_infrastructure', name_en: 'Qatar Infrastructure', name_ur: 'قطر انفراسٹرکچر' },
  { code: 'qatar_energy', name_en: 'Qatar Energy', name_ur: 'قطر انرجی' },
  { code: 'saudi_construction', name_en: 'Saudi Construction', name_ur: 'سعودی تعمیرات' }
].each do |attributes|
  project = Project.find_or_initialize_by(code: attributes.fetch(:code))
  project.assign_attributes(name_en: attributes.fetch(:name_en), name_ur: attributes.fetch(:name_ur), active: true)
  project.save!
end

[
  { code: 'electrician', name_en: 'Electrician', name_ur: 'الیکٹریشن' },
  { code: 'plumber', name_en: 'Plumber', name_ur: 'پلمبر' },
  { code: 'welder', name_en: 'Welder', name_ur: 'ویلڈر' },
  { code: 'mason', name_en: 'Mason', name_ur: 'مستری' },
  { code: 'steel_fixer', name_en: 'Steel Fixer', name_ur: 'اسٹیل فکسر' }
].each do |attributes|
  craft = Craft.find_or_initialize_by(code: attributes.fetch(:code))
  craft.assign_attributes(name_en: attributes.fetch(:name_en), name_ur: attributes.fetch(:name_ur), active: true)
  craft.save!
end

# Codes match the document types the candidate-admin frontend already
# renders (web/src/app/admin/candidates/[id]/page.jsx's documentTypeKeys),
# keeping the two sides of this contract-first build aligned.
[
  { code: 'passport', name_en: 'Passport', name_ur: 'پاسپورٹ', requires_number: true, requires_expiry: true },
  { code: 'cnic_front', name_en: 'CNIC (Front)', name_ur: 'شناختی کارڈ (اگلا رخ)' },
  { code: 'cnic_back', name_en: 'CNIC (Back)', name_ur: 'شناختی کارڈ (پچھلا رخ)' },
  { code: 'next_of_kin_cnic', name_en: 'Next of Kin CNIC', name_ur: 'قریبی رشتہ دار کا شناختی کارڈ' },
  { code: 'police_character', name_en: 'Police Character Certificate', name_ur: 'پولیس کریکٹر سرٹیفکیٹ',
    requires_expiry: true },
  { code: 'bank_details', name_en: 'Bank Account Details', name_ur: 'بینک اکاؤنٹ کی تفصیلات' },
  { code: 'cheque_image', name_en: 'Cancelled Cheque Image', name_ur: 'منسوخ شدہ چیک کی تصویر' },
  { code: 'cv', name_en: 'CV / Resume', name_ur: 'سی وی / ریزیومے' }
].each do |attributes|
  document_type = DocumentType.find_or_initialize_by(code: attributes.fetch(:code))
  document_type.assign_attributes(
    name_en: attributes.fetch(:name_en),
    name_ur: attributes.fetch(:name_ur),
    requires_number: attributes.fetch(:requires_number, false),
    requires_expiry: attributes.fetch(:requires_expiry, false),
    active: true
  )
  document_type.save!
end

# --- Demo/reserved data for exercising MPS-201's candidate OTP API ---------
#
# Reserved test CNIC values (see README for the documented, frontend-facing
# copy of this table):
#
#   11111-1111111-1  seeded, valid mobile   -> full OTP request+verify success
#   22222-2222222-2  seeded, undeliverable  -> OTP request "succeeds" (generic
#                     mobile (+920000000000)   response) but SMS delivery fails
#                                                internally (Sms::Providers::
#                                                TestProvider's reserved
#                                                all-zeros pattern)
#   99999-9999999-9  deliberately NEVER      -> exercises the "unknown CNIC"
#                     seeded                    path; always returns the same
#                                                generic response as the two
#                                                CNICs above
#
# All values are synthetic and match no real person.
seed_user = User.find_or_create_by!(email: 'seed-data@descon.local') do |user|
  user.password = SecureRandom.hex(32)
  user.role = 'admin'
  user.active = true
end

[
  { cnic: '11111-1111111-1', full_name: 'OTP Demo Candidate (Valid Mobile)', mobile_number: '+923001234567' },
  { cnic: '22222-2222222-2', full_name: 'OTP Demo Candidate (Undeliverable Mobile)', mobile_number: '+920000000000' }
].each do |attributes|
  candidate = Candidate.find_or_initialize_by(cnic: attributes.fetch(:cnic))
  candidate.assign_attributes(
    full_name: attributes.fetch(:full_name),
    mobile_number: attributes.fetch(:mobile_number),
    preferred_locale: 'en',
    source_code: 'admin_ui',
    created_by: seed_user
  )
  candidate.save!
end

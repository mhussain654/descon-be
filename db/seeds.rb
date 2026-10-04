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
    trigger_ai_calls
    manage_ai_call_scripts
    view_candidate_assignments
    view_workflow
  ],
  'mps' => %w[
    view_candidates
    manage_candidate_assignments
    manage_candidate_documents
    manage_workflow
    manage_communications
    trigger_ai_calls
    manage_ai_call_scripts
    view_mps_dashboard
    view_reports
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
    view_management_dashboard
    view_reports
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

# --- AI voice call scripts (MPS-708) ----------------------------------------
# Seeded inactive so nothing gets called until an admin reviews and enables
# it. Only stages where an automated call plausibly makes sense get a
# default row; admin can still enable/edit any of these later, but cannot
# add a stage outside this fixed set (see WorkflowStageCallScript's
# inclusion validation). Both languages are seeded for every stage --
# WorkflowStageAnnouncementPrompt selects between them per candidate at
# call time (see its own doc comment), so a stage needs both ready, not
# just one. `{{candidate_name}}` is an ElevenLabs dynamic-variable
# placeholder, substituted provider-side -- not literal text.
{
  'verified' => {
    en: 'Hello {{candidate_name}}, this is Descon Manpower calling -- your documents have been verified.',
    ur: 'السلام علیکم {{candidate_name}}، یہ ڈیسکون مین پاور کی کال ہے -- آپ کی دستاویزات کی تصدیق ہو گئی ہے۔'
  },
  'fee_paid' => {
    en: 'Hello {{candidate_name}}, this is Descon Manpower calling to confirm your fee payment was received.',
    ur: 'السلام علیکم {{candidate_name}}، یہ ڈیسکون مین پاور کی کال ہے یہ تصدیق کرنے کے لیے کہ آپ کی فیس کی ' \
        'ادائیگی موصول ہو گئی ہے۔'
  },
  'qvc_completed_outcome_received' => {
    en: 'Hello {{candidate_name}}, this is Descon Manpower calling about your QVC appointment outcome.',
    ur: 'السلام علیکم {{candidate_name}}، یہ ڈیسکون مین پاور کی کال ہے آپ کے QVC اپائنٹمنٹ کے نتیجے کے بارے میں۔'
  },
  'visa_issued_or_rejected' => {
    en: 'Hello {{candidate_name}}, this is Descon Manpower calling with an update on your visa.',
    ur: 'السلام علیکم {{candidate_name}}، یہ ڈیسکون مین پاور کی کال ہے آپ کے ویزا کے بارے میں تازہ ترین اطلاع کے ساتھ۔'
  },
  'appeared_for_protection' => {
    en: 'Hello {{candidate_name}}, this is Descon Manpower calling following your protection appearance.',
    ur: 'السلام علیکم {{candidate_name}}، یہ ڈیسکون مین پاور کی کال ہے آپ کی پروٹیکشن حاضری کے بعد۔'
  },
  'mobilized' => {
    en: 'Hello {{candidate_name}}, this is Descon Manpower calling to confirm your mobilization.',
    ur: 'السلام علیکم {{candidate_name}}، یہ ڈیسکون مین پاور کی کال ہے آپ کی روانگی کی تصدیق کے لیے۔'
  }
}.each do |stage_code, announcements|
  script = WorkflowStageCallScript.find_or_initialize_by(workflow_stage_code: stage_code)
  script.announcement_en ||= announcements.fetch(:en)
  script.announcement_ur ||= announcements.fetch(:ur)
  script.active = false if script.new_record?
  script.save!
end

# --- AI call operational settings (MPS-712) ---------------------------------
# Seeds the singleton row up front so it's visible to an admin immediately,
# rather than only appearing on first lazy access. Every column stays nil
# (AiCallOperationalSetting.current would create it the same way regardless)
# -- an environment that never touches the admin UI keeps its existing
# ENV-driven AiCalls::Configuration defaults unchanged.
AiCallOperationalSetting.current

# --- Training link setting ---------------------------------------------------
# Seeds the singleton row up front (with its placeholder default URL --
# TrainingSetting::DEFAULT_URL) so both the admin settings screen and the
# candidate Training page are never empty before the client provides their
# real training link.
TrainingSetting.current

# --- Support number setting --------------------------------------------------
# Seeds the (blank) singleton row so the admin settings screen always has a
# record to edit; the candidate "Help & support" action stays unavailable
# until staff enter the real helpline number.
SupportSetting.current

# --- Reference catalogs (MPS-106) -------------------------------------------

[
  { code: 'qatar', name_en: 'Qatar', name_ur: 'قطر' },
  { code: 'saudi_arabia', name_en: 'Saudi Arabia', name_ur: 'سعودی عرب' },
  { code: 'uae', name_en: 'United Arab Emirates', name_ur: 'متحدہ عرب امارات' },
  { code: 'oman', name_en: 'Oman', name_ur: 'عمان' },
  { code: 'kuwait', name_en: 'Kuwait', name_ur: 'کویت' },
  { code: 'azerbaijan', name_en: 'Azerbaijan', name_ur: 'آذربائیجان' },
  { code: 'south_africa', name_en: 'South Africa', name_ur: 'جنوبی افریقہ' }
].each do |attributes|
  country = Country.find_or_initialize_by(code: attributes.fetch(:code))
  country.assign_attributes(name_en: attributes.fetch(:name_en), name_ur: attributes.fetch(:name_ur), active: true)
  country.save!
end

# Country mobilization processes: publishes each approved version once (needs
# the workflow stage catalog and countries above). A published version never
# changes -- see MobilizationProcesses::Definitions.
MobilizationProcesses::Seeder.call

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
  { code: 'steel_fixer', name_en: 'Steel Fixer', name_ur: 'اسٹیل فکسر' },
  { code: 'driver', name_en: 'Driver', name_ur: 'ڈرائیور', is_driver: true },
  { code: 'heavy_vehicle_driver', name_en: 'Heavy Vehicle Driver', name_ur: 'ہیوی گاڑی ڈرائیور', is_driver: true }
].each do |attributes|
  craft = Craft.find_or_initialize_by(code: attributes.fetch(:code))
  craft.assign_attributes(name_en: attributes.fetch(:name_en), name_ur: attributes.fetch(:name_ur), active: true,
                          is_driver: attributes.fetch(:is_driver, false))
  craft.save!
end

# Document catalog plus the common, KSA and Qatar checklists (with upload
# rules and bilingual instructions) -- see DocumentChecklists::Definitions.
# Needs the countries above.
DocumentChecklists::Seeder.call

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
#                     seeded                    path; returns a 404
#                                                candidate_cnic_not_found
#                                                error instead of a generic
#                                                response (a deliberate,
#                                                client-approved disclosure
#                                                -- see
#                                                CandidateCnicNotFoundError)
#
# All values are synthetic and match no real person.
#
# Skipped in the test environment: `db:prepare` runs this file for real
# (not inside a rolled-back RSpec transaction) against a freshly created
# database, e.g. in CI. Every other seed above (roles, permissions, workflow
# stages, reference catalogs) has always been safe to leave in place because
# nothing in the existing spec suite assumed zero rows in those tables --
# but this is the first seed content that creates a User (needed only to
# satisfy Candidate#created_by) and a Candidate, and pre-existing specs
# (e.g. Idempotency::RequestHandler's `User.delete_all` cleanup, the users
# index pagination spec) assumed `db:seed` never touches those tables. These
# demo candidates exist for manual/frontend exploratory testing against a
# real running server (see README), not as automated-test fixtures, so
# skipping them in test is correct, not just a workaround.
if Rails.env.development? && ENV.fetch('SEED_DEMO_DATA', 'false') == 'true'
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
end

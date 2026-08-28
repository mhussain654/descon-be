# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    sequence(:code) { |n| "role_#{n}" }
    system_defined { false }
    active { true }

    trait :admin do
      code { 'admin' }
      system_defined { true }
    end

    trait :hr do
      code { 'hr' }
      system_defined { true }
    end

    trait :mps do
      code { 'mps' }
      system_defined { true }
    end

    trait :finance do
      code { 'finance' }
      system_defined { true }
    end

    trait :management do
      code { 'management' }
      system_defined { true }
    end
  end

  factory :permission do
    sequence(:code) { |n| "permission_#{n}" }
    system_defined { false }
    active { true }
  end

  factory :role_permission do
    role
    permission
  end

  factory :country do
    code { "test_country_#{SecureRandom.hex(6)}" }
    sequence(:name_en) { |n| "Country #{n}" }
    sequence(:name_ur) { |n| "ملک #{n}" }
    active { true }
  end

  factory :project do
    code { "test_project_#{SecureRandom.hex(6)}" }
    sequence(:name_en) { |n| "Project #{n}" }
    sequence(:name_ur) { |n| "پروجیکٹ #{n}" }
    active { true }
  end

  factory :craft do
    code { "test_craft_#{SecureRandom.hex(6)}" }
    sequence(:name_en) { |n| "Craft #{n}" }
    sequence(:name_ur) { |n| "کرافٹ #{n}" }
    active { true }
  end

  factory :workflow_stage do
    initialize_with { WorkflowStage.find_or_initialize_by(code: code) }

    sequence(:position) { |n| n + 100 }
    code { "test_workflow_stage_#{SecureRandom.hex(6)}" }
    system_defined { false }
    active { true }

    trait :registered do
      position { 1 }
      code { 'registered' }
      system_defined { true }
    end
  end

  factory :candidate do
    sequence(:full_name) { |n| "Candidate #{n}" }
    cnic do
      digits = SecureRandom.random_number(10_000_000)
      suffix = SecureRandom.random_number(10)
      "#{format('%05d', 42_000 + SecureRandom.random_number(10_000))}-#{format('%07d', digits)}-#{suffix}"
    end
    mobile_number { "+923#{format('%09d', SecureRandom.random_number(1_000_000_000))}" }
    passport_number { nil }
    preferred_locale { 'en' }
    status_code { 'registered' }
    active { true }
    source_code { 'admin_ui' }
    association :created_by, factory: :user
  end

  factory :candidate_session do
    candidate
    public_id { SecureRandom.uuid }
    jti { SecureRandom.uuid }
    user_agent { 'RSpec' }
    ip_address { '127.0.0.1' }
    revoked_at { nil }
    last_seen_at { nil }
  end

  factory :candidate_refresh_token do
    candidate_session
    token_digest { Digest::SHA256.hexdigest(SecureRandom.hex(48)) }
    expires_at { CandidateRefreshToken::EXPIRY_WINDOW.from_now }
    revoked_at { nil }
    rotated_at { nil }
    replaced_by_id { nil }
  end

  factory :candidate_otp_challenge do
    candidate
    cnic { candidate&.cnic }
    code_digest { BCrypt::Password.create('123456') }
    expires_at { CandidateOtpChallenge::EXPIRY_WINDOW.from_now }
    consumed_at { nil }
    attempts { 0 }
    requested_ip { '127.0.0.1' }

    trait :expired do
      expires_at { 1.minute.ago }
    end

    trait :consumed do
      consumed_at { Time.current }
    end

    trait :locked do
      attempts { CandidateOtpChallenge::MAX_ATTEMPTS }
    end

    # A challenge for a CNIC that does not resolve to any real candidate.
    trait :decoy do
      candidate { nil }
      sequence(:cnic) { |n| "#{format('%05d', 90_000 + n)}-#{format('%07d', 9_000_000 + n)}-9" }
    end
  end

  factory :document_type do
    code { "test_document_type_#{SecureRandom.hex(6)}" }
    sequence(:name_en) { |n| "Document Type #{n}" }
    sequence(:name_ur) { |n| "دستاویز کی قسم #{n}" }
    active { true }
    requires_number { false }
    requires_expiry { false }
  end

  factory :document_requirement do
    document_type
    country { nil }
    project { nil }
    craft { nil }
    required { true }
    active { true }
  end

  factory :candidate_assignment do
    candidate
    country
    project
    craft
    association :current_workflow_stage, factory: %i[workflow_stage registered]
    association :created_by, factory: :user
    reference_number { "DES-#{SecureRandom.hex(6).upcase}" }
    qvc_outcome_code { nil }
    qvc_outcome_date { nil }
  end

  factory :candidate_stage_history do
    candidate_assignment
    from_workflow_stage { association(:workflow_stage, :registered) }
    to_workflow_stage { association(:workflow_stage) }
    actor { nil }
    occurred_at { Time.current }
    reason_code { nil }
    note { nil }
  end

  factory :candidate_document do
    candidate_assignment
    document_type
    association :uploaded_by, factory: :user
    verified_by { nil }
    status_code { 'uploaded' }
    original_filename { 'document.pdf' }
    content_type { 'application/pdf' }
    byte_size { 1024 }
    checksum_sha256 { 'a' * 64 }
    document_number { 'DOC-001' }
    issued_on { Date.current }
    expires_on { nil }
    uploaded_at { Time.current }
    verified_at { nil }
    rejection_reason { nil }

    after(:build) do |document|
      next if document.file.attached?

      document.file.attach(
        io: Rails.root.join('spec/fixtures/files/test.pdf').open,
        filename: 'document.pdf',
        content_type: 'application/pdf'
      )
    end
  end

  factory :candidate_document_submission do
    candidate_assignment
    public_id { SecureRandom.uuid }
    status_code { 'submitted' }
    request_id { SecureRandom.uuid }
    submitted_at { Time.current }
  end

  factory :candidate_document_submission_item do
    candidate_document_submission
    candidate_document
    requirement_code { candidate_document.document_type.code }
    required { true }
  end

  factory :payment do
    candidate_assignment
    association :recorded_by, factory: :user
    payment_type_code { 'onboarding_fee' }
    status_code { 'paid' }
    amount { 1500.0 }
    currency_code { 'PKR' }
    external_reference { nil }
    paid_at { Time.current }
    note { nil }
  end

  factory :communication do
    candidate_assignment
    association :initiated_by, factory: :user
    channel_code { 'sms' }
    direction_code { 'outbound' }
    status_code { 'sent' }
    template_code { 'welcome_message' }
    locale { 'en' }
    recipient_masked { '+92300*****12' }
    provider_reference { nil }
    sent_at { Time.current }
    delivered_at { nil }
    failed_at { nil }
    error_code { nil }
  end

  factory :audit_event do
    candidate_assignment
    candidate { candidate_assignment.candidate }
    association :actor, factory: :user
    entity_type { 'CandidateAssignment' }
    entity_id { candidate_assignment.id || 1 }
    action_code { 'created' }
    reason_code { nil }
    note { nil }
    request_id { SecureRandom.uuid }
    metadata { {} }
    occurred_at { Time.current }
  end
end

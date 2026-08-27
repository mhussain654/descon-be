# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { "test_user_#{SecureRandom.hex(6)}@example.com" }
    password { 'Password123!' }
    public_id { SecureRandom.uuid }
    role { 'hr' }
    active { true }
    staff_state { 'active' }
    invitation_token_digest { nil }
    invitation_sent_at { nil }
    invitation_expires_at { nil }
    invitation_accepted_at { nil }
    invited_by { nil }

    after(:build) do |user|
      Role.find_or_create_by!(code: user.role) do |role|
        role.system_defined = Role::SYSTEM_ROLES.any? { |role_attributes| role_attributes.fetch(:code) == user.role }
        role.active = true
      end
    end

    trait :invited do
      password { nil }
      encrypted_password { '' }
      staff_state { 'invited' }
      active { false }
      invitation_token_digest { nil }
      invitation_sent_at { nil }
      invitation_expires_at { nil }
    end

    trait :issued_invitation do
      invited
      invitation_token_digest { Digest::SHA256.hexdigest(SecureRandom.hex(32)) }
      invitation_sent_at { Time.current }
      invitation_expires_at { User::INVITATION_TTL.from_now }
    end

    trait :suspended do
      staff_state { 'suspended' }
      active { false }
    end
  end

  factory :session do
    user
    public_id { SecureRandom.uuid }
    jti { SecureRandom.uuid }
    user_agent { 'RSpec' }
    ip_address { '127.0.0.1' }
    revoked_at { nil }
    last_seen_at { nil }
  end

  factory :refresh_token do
    session
    token_digest { Digest::SHA256.hexdigest(SecureRandom.hex(48)) }
    expires_at { RefreshToken::EXPIRY_WINDOW.from_now }
    revoked_at { nil }
    rotated_at { nil }
    replaced_by_id { nil }
  end

  factory :authentication_event do
    user
    session { nil }
    event_code { 'login_succeeded' }
    request_id { SecureRandom.uuid }
    identifier_masked { 'u***r@example.com' }
    ip_address { '127.0.0.1' }
    user_agent { 'RSpec' }
    metadata { {} }
    occurred_at { Time.current }
  end

  factory :idempotency_key do
    idempotency_scope { 'test.scope' }
    key_digest { Digest::SHA256.hexdigest("key-#{SecureRandom.hex(8)}") }
    request_fingerprint { Digest::SHA256.hexdigest("fingerprint-#{SecureRandom.hex(8)}") }
    request_method { 'POST' }
    request_path { '/test/path' }
    status { IdempotencyKey::PROCESSING_STATUS }
    subject { nil }
    response_status { nil }
    response_payload { nil }
    completed_at { nil }
    expires_at { 12.hours.from_now }

    trait :completed do
      status { IdempotencyKey::COMPLETED_STATUS }
      response_status { 200 }
      response_payload do
        {
          'type' => 'success',
          'data' => { 'revoked' => true },
          'status' => 'ok',
          'meta' => { 'timestamp' => Time.current.utc.iso8601 }
        }
      end
      completed_at { Time.current }
    end
  end
end

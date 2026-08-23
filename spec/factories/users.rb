# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'Password123!' }
    public_id { SecureRandom.uuid }
    role { 'hr' }
    active { true }

    after(:build) do |user|
      next if Role.exists?(code: user.role)

      create(
        :role,
        code: user.role,
        system_defined: Role::SYSTEM_ROLES.any? { |role_attributes| role_attributes.fetch(:code) == user.role }
      )
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

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
end

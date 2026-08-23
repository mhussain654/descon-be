# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'Password123!' }
    public_id { SecureRandom.uuid }
    role { 'staff' }
    active { true }

    after(:build) do |user|
      next if Role.exists?(code: user.role)

      create(:role, user.role == 'admin' ? :admin : :staff)
    end
  end
end

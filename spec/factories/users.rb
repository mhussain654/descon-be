# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'Password123!' }
    public_id { SecureRandom.uuid }
    role { 'member' }
    active { true }
  end
end

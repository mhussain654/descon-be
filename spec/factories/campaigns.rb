# frozen_string_literal: true

FactoryBot.define do
  factory :campaign do
    code { "CAMPAIGN-#{SecureRandom.hex(6).upcase}" }
    sequence(:name) { |n| "Campaign #{n}" }
    kind { 'regular' }
    country
    active { true }

    # The single Test campaign: reuse it when it already exists (it is unique).
    trait :test do
      kind { 'test' }
      code { 'TEST' }
      name { 'Test campaign' }
      country { nil }
      initialize_with { Campaign.find_or_initialize_by(kind: 'test') }
    end
  end
end

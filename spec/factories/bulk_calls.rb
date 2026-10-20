# frozen_string_literal: true

FactoryBot.define do
  factory :robocall_voice do
    sequence(:name_en) { |n| "Call type #{n}" }
    sequence(:voice_id) { |n| (100 + n).to_s }
    active { true }
  end

  factory :bulk_call_batch do
    association :created_by, factory: :user
    robocall_voice
    provider_voice_id { robocall_voice.voice_id }
    voice_name { robocall_voice.name_en }
    workflow_stage_code { 'verified' }
    requested_limit { 200 }
    selected_count { 1 }
  end

  factory :bulk_call_batch_item do
    bulk_call_batch
    candidate
    candidate_assignment { association(:candidate_assignment, candidate:) }
    status { 'queued' }
  end
end

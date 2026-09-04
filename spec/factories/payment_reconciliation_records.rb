# frozen_string_literal: true

FactoryBot.define do
  factory :payment_reconciliation_run do
    sequence(:run_date) { |n| Date.current - n.days }
    status_code { 'completed' }
    started_at { Time.current }
    completed_at { Time.current }
    initiated_by { nil }
    summary { {} }
  end

  factory :payment_reconciliation_finding do
    payment_reconciliation_run
    payment
    finding_code { 'external_reference_missing' }
    state_code { 'open' }
    details { { 'payment_public_id' => payment.public_id } }
  end
end

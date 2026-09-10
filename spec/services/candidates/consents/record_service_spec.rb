# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Consents::RecordService do
  it 'creates a consent row for the current policy version with the given ip address' do
    candidate = create(:candidate, :without_consent)

    consent = described_class.call(candidate:, ip_address: '203.0.113.5')

    expect(consent).to be_persisted
    expect(consent.policy_version).to eq(CandidateConsent::CURRENT_POLICY_VERSION)
    expect(consent.ip_address).to eq('203.0.113.5')
    expect(consent.accepted_at).to be_present
  end

  it 'is idempotent when the candidate already accepted the current policy version' do
    candidate = create(:candidate)
    existing = candidate.candidate_consents.find_by(policy_version: CandidateConsent::CURRENT_POLICY_VERSION)

    expect do
      described_class.call(candidate:, ip_address: '203.0.113.5')
    end.not_to change(CandidateConsent, :count)

    expect(described_class.call(candidate:, ip_address: '203.0.113.5')).to eq(existing)
  end

  it 'returns the winning row instead of raising when a concurrent request inserts first (check-then-act race)' do
    candidate = create(:candidate, :without_consent)
    service = described_class.new(candidate:, ip_address: '203.0.113.5')
    winning_consent = nil

    # Simulates the race directly rather than via real threads: the
    # existence check already ran and found nothing (that's why call
    # reached create_consent! at all), then a concurrent request's insert
    # wins first, so this one hits the DB's unique index instead.
    allow(service).to receive(:create_consent!) do
      winning_consent = candidate.candidate_consents.create!(
        policy_version: CandidateConsent::CURRENT_POLICY_VERSION,
        accepted_at: Time.current,
        ip_address: '198.51.100.9'
      )
      raise ActiveRecord::RecordNotUnique, 'simulated concurrent insert'
    end

    expect(service.call).to eq(winning_consent)
  end
end

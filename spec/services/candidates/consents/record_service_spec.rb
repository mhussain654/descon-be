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
end

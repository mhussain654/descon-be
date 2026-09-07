# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateConsent do
  it 'is valid with a candidate, policy version and accepted_at' do
    consent = build(:candidate_consent)

    expect(consent).to be_valid
  end

  it 'assigns a public_id on creation' do
    consent = create(:candidate_consent)

    expect(consent.public_id).to be_present
  end

  it 'requires policy_version and accepted_at' do
    consent = build(:candidate_consent, policy_version: nil, accepted_at: nil)

    expect(consent).not_to be_valid
    expect(consent.errors[:policy_version]).to be_present
    expect(consent.errors[:accepted_at]).to be_present
  end

  it 'only allows one row per candidate per policy version' do
    candidate = create(:candidate)
    create(:candidate_consent, candidate:, policy_version: 'v1')

    duplicate = build(:candidate_consent, candidate:, policy_version: 'v1')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:candidate_id]).to be_present
  end

  it 'is immutable once created' do
    consent = create(:candidate_consent)

    expect { consent.update!(ip_address: '10.0.0.1') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { consent.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  describe '.current_policy_accepted?' do
    it 'is true only when a row exists for the current policy version' do
      accepted_candidate = create(:candidate)
      pending_candidate = create(:candidate, :without_consent)

      expect(described_class.current_policy_accepted?(accepted_candidate)).to be(true)
      expect(described_class.current_policy_accepted?(pending_candidate)).to be(false)
    end
  end
end

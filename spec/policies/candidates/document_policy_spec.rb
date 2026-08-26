# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::DocumentPolicy, type: :policy do
  let(:candidate) { create(:candidate) }

  it 'allows an active candidate to view and upload their own documents' do
    policy = described_class.new(candidate, candidate)

    expect(policy.index?).to be(true)
    expect(policy.create?).to be(true)
  end

  it 'denies access for inactive candidates' do
    inactive_candidate = create(:candidate, active: false)
    policy = described_class.new(inactive_candidate, inactive_candidate)

    expect(policy.index?).to be(false)
    expect(policy.create?).to be(false)
  end

  it 'denies access to another candidate record' do
    other_candidate = create(:candidate)
    policy = described_class.new(candidate, other_candidate)

    expect(policy.index?).to be(false)
    expect(policy.create?).to be(false)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::TrainingSettingPolicy do
  it 'allows any active candidate to view the shared training link -- no ownership check' do
    candidate = create(:candidate)
    other_candidate = create(:candidate)

    expect(described_class.new(candidate, candidate).show?).to be(true)
    # Unlike WorkflowPolicy/ProfilePolicy, a mismatched record is still allowed --
    # training content isn't per-candidate, so there's nothing to own.
    expect(described_class.new(candidate, other_candidate).show?).to be(true)
  end

  it 'denies an inactive candidate' do
    candidate = create(:candidate, active: false)

    expect(described_class.new(candidate, candidate).show?).to be(false)
  end

  it 'denies an unauthenticated actor' do
    expect(described_class.new(nil, nil).show?).to be(false)
  end
end

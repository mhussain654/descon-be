# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::BankDetailPolicy do
  it 'allows active candidates to view and update their bank details' do
    candidate = create(:candidate)
    policy = described_class.new(candidate, candidate)

    expect(policy.show?).to be(true)
    expect(policy.update?).to be(true)
  end

  it 'denies inactive or missing candidates' do
    inactive_candidate = create(:candidate, active: false)

    expect(described_class.new(inactive_candidate, inactive_candidate).show?).to be(false)
    expect(described_class.new(nil, inactive_candidate).update?).to be(false)
  end
end

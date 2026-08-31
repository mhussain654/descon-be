# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::WorkflowPolicy do
  it 'allows candidates to read only their own workflow state and history' do
    candidate = create(:candidate)
    other_candidate = create(:candidate)

    expect(described_class.new(candidate, candidate).show?).to be(true)
    expect(described_class.new(candidate, candidate).history?).to be(true)
    expect(described_class.new(candidate, candidate).access?).to be(true)
    expect(described_class.new(candidate, other_candidate).show?).to be(false)
    expect(described_class.new(candidate, other_candidate).history?).to be(false)
    expect(described_class.new(candidate, other_candidate).access?).to be(false)
  end
end

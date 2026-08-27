# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::ApplicationProgressPolicy do
  let(:candidate) { create(:candidate) }

  it 'allows an active candidate to view their own progress' do
    expect(described_class.new(candidate, candidate).show?).to be(true)
  end

  it 'denies access for a different candidate' do
    expect(described_class.new(create(:candidate), candidate).show?).to be(false)
  end

  it 'denies access for an inactive candidate' do
    candidate.update!(active: false)

    expect(described_class.new(candidate, candidate).show?).to be(false)
  end
end

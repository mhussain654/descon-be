# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::ConsentPolicy do
  subject(:policy) { described_class.new(candidate, candidate) }

  context 'when the candidate is active' do
    let(:candidate) { build_stubbed(:candidate, active: true) }

    it 'permits show and create' do
      expect(policy.show?).to be(true)
      expect(policy.create?).to be(true)
    end
  end

  context 'when the candidate is inactive' do
    let(:candidate) { build_stubbed(:candidate, active: false) }

    it 'forbids show and create' do
      expect(policy.show?).to be(false)
      expect(policy.create?).to be(false)
    end
  end

  context 'when there is no authenticated candidate' do
    let(:candidate) { nil }

    it 'forbids show and create' do
      expect(policy.show?).to be(false)
      expect(policy.create?).to be(false)
    end
  end
end

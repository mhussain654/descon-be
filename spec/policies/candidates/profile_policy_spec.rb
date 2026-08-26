# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::ProfilePolicy do
  describe '#show?' do
    it 'allows an active candidate to view only their own profile' do
      candidate = create(:candidate, active: true)
      other_candidate = create(:candidate, active: true)

      expect(described_class.new(candidate, candidate).show?).to be(true)
      expect(described_class.new(candidate, other_candidate).show?).to be(false)
    end

    it 'denies inactive or unauthenticated candidates' do
      inactive_candidate = create(:candidate, active: false)

      expect(described_class.new(inactive_candidate, inactive_candidate).show?).to be(false)
      expect(described_class.new(nil, inactive_candidate).show?).to be(false)
    end
  end
end

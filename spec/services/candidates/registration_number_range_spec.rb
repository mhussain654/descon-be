# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::RegistrationNumberRange do
  describe '.call' do
    it 'reads one number as a one-number range' do
      expect(described_class.call(' 900005 ')).to eq(900_005..900_005)
    end

    it 'reads a range in either order, with or without spaces' do
      expect(described_class.call('900001-900050')).to eq(900_001..900_050)
      expect(described_class.call('900050 - 900001')).to eq(900_001..900_050)
    end

    it 'returns nil for anything else' do
      ['', 'abc', '9000-', '-9000', '1-2-3', '1' * 16].each do |value|
        expect(described_class.call(value)).to be_nil
      end
    end
  end
end

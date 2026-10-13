# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::Imports::RejectedValue do
  def rejected(field, value)
    described_class.call(field:, source_values: { field => value, 'full_name' => 'Other Column' })
  end

  describe '.call' do
    it "returns only the error column's own cell, squished" do
      expect(rejected('craft_code', ' Crane  Opereator ')).to eq('Crane Opereator')
    end

    it 'returns nil for a blank cell, a missing column, or a row-level error' do
      expect(rejected('reference_number', '  ')).to be_nil
      expect(described_class.call(field: 'country_code', source_values: {})).to be_nil
      expect(rejected('row', 'anything')).to be_nil
    end

    it 'masks a well-formed CNIC the same way as everywhere else in the app' do
      expect(rejected('cnic', '35200-8469419-3')).to eq('35200-*******-3')
      expect(rejected('next_of_kin_cnic', '3520084694193')).to eq('35200-*******-3')
    end

    it 'still masks a malformed CNIC, which is usually a complete number with a typo' do
      expect(rejected('cnic', '42101-123456-1')).to eq('42**********-1')
    end

    it 'masks mobile numbers, including ones too short for the phone masker' do
      expect(rejected('mobile_number', '923364449293')).to eq('923364****93')
      expect(rejected('next_of_kin_mobile_number', '12345')).to eq('*****')
    end

    it 'masks passport numbers' do
      expect(rejected('passport_number', 'AB1234567')).to eq('AB*****67')
    end
  end
end

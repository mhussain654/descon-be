# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoneNumbers::Masker do
  it 'masks the middle digits, keeping a 6-char prefix and 2-char suffix' do
    expect(described_class.call('+923001234512')).to eq('+92300*****12')
  end

  it 'returns short input unmasked' do
    expect(described_class.call('12345678')).to eq('12345678')
  end

  it 'handles blank input without raising' do
    expect(described_class.call(nil)).to eq('')
    expect(described_class.call('')).to eq('')
  end
end

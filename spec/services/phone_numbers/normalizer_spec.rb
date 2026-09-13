# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoneNumbers::Normalizer do
  it 'strips whitespace and keeps only digits, preserving a leading +' do
    expect(described_class.call(' +92 300 1234512 ')).to eq('+923001234512')
    expect(described_class.call('0300-1234512')).to eq('03001234512')
  end

  it 'returns an empty string for input with no digits' do
    expect(described_class.call('abc')).to eq('')
    expect(described_class.call(nil)).to eq('')
    expect(described_class.call('')).to eq('')
  end
end

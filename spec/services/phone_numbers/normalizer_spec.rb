# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoneNumbers::Normalizer do
  it 'converts a local Pakistani number into canonical E.164' do
    expect(described_class.call('0300-1234512')).to eq('+923001234512')
    expect(described_class.call('03001234512')).to eq('+923001234512')
  end

  it 'preserves an already-E.164 number, stripping only formatting' do
    expect(described_class.call(' +92 300 1234512 ')).to eq('+923001234512')
  end

  it 'produces the same canonical value for equivalent local and international forms' do
    expect(described_class.call('03001234512')).to eq(described_class.call('+923001234512'))
  end

  it 'adds the country code to a national number missing its leading trunk zero' do
    expect(described_class.call('3001234512')).to eq('+923001234512')
  end

  it 'does not double-prefix a number already carrying the country code without a plus' do
    expect(described_class.call('923001234512')).to eq('+923001234512')
  end

  it 'returns an empty string for input with no digits' do
    expect(described_class.call('abc')).to eq('')
    expect(described_class.call(nil)).to eq('')
    expect(described_class.call('')).to eq('')
  end
end

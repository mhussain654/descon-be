# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::TranscriptRedactor do
  it 'redacts a dashed CNIC' do
    expect(described_class.call('My CNIC is 42101-1234567-1, thanks.'))
      .to eq('My CNIC is [redacted-cnic], thanks.')
  end

  it 'redacts a 13-digit CNIC spoken without dashes' do
    expect(described_class.call('It is 4210112345671 if that helps.'))
      .to eq('It is [redacted-cnic] if that helps.')
  end

  it 'redacts a spoken 6-digit verification code' do
    expect(described_class.call('The code is 482913, did you get it?'))
      .to eq('The code is [redacted-code], did you get it?')
  end

  it 'leaves ordinary text untouched' do
    expect(described_class.call('Hello, this is Descon Manpower.')).to eq('Hello, this is Descon Manpower.')
  end

  it 'handles blank input without raising' do
    expect(described_class.call(nil)).to be_nil
    expect(described_class.call('')).to eq('')
  end
end

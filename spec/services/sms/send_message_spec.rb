# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sms::SendMessage do
  describe '.call' do
    it 'delegates to the configured provider and returns its DeliveryResult' do
      result = described_class.call(to: '+923001234567', body: 'hello')
      expect(result).to be_a(Sms::DeliveryResult)
      expect(result).to be_success
    end

    it 'raises ProviderNotConfiguredError for an unknown SMS_PROVIDER value' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SMS_PROVIDER', 'test').and_return('unknown_vendor')

      expect { described_class.call(to: '+923001234567', body: 'hello') }
        .to raise_error(Sms::ProviderNotConfiguredError, /unknown_vendor/i)
    end
  end
end

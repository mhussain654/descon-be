# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sms::SendMessage do
  describe '.call' do
    it 'delegates to the configured provider and returns its DeliveryResult' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SMS_PROVIDER', 'test').and_return('test')

      result = described_class.call(to: '+923001234567', body: 'hello')
      expect(result).to be_a(Sms::DeliveryResult)
      expect(result).to be_success
    end

    it 'routes to the real send.pk provider when SMS_PROVIDER=sendpk, never touching the network without credentials' do
      # Stubbed explicitly rather than relying on these being unset in the
      # ambient environment -- .env is loaded for this test process too, and
      # a real SENDPK_API_KEY/SENDPK_SENDER_ID may legitimately be present
      # there once send.pk is actually configured for manual testing.
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).with('SMS_PROVIDER', 'test').and_return('sendpk')
      allow(ENV).to receive(:[]).with('SENDPK_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('SENDPK_SENDER_ID').and_return(nil)
      allow(Net::HTTP).to receive(:start)

      result = described_class.call(to: '+923001234567', body: 'hello')

      expect(result).to be_a(Sms::DeliveryResult)
      expect(result).not_to be_success
      expect(result.error_code).to eq('not_configured')
      expect(Net::HTTP).not_to have_received(:start)
    end

    it 'raises ProviderNotConfiguredError for an unknown SMS_PROVIDER value' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SMS_PROVIDER', 'test').and_return('unknown_vendor')

      expect { described_class.call(to: '+923001234567', body: 'hello') }
        .to raise_error(Sms::ProviderNotConfiguredError, /unknown_vendor/i)
    end
  end
end

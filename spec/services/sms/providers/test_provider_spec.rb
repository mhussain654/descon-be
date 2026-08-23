# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sms::Providers::TestProvider do
  describe '#deliver' do
    it 'succeeds for an ordinary mobile number, returning a provider reference' do
      result = described_class.new.deliver(to: '+923001234567', body: 'test message')

      expect(result).to be_success
      expect(result.provider_reference).to be_present
      expect(result.error_code).to be_nil
    end

    it 'fails for the reserved undeliverable number pattern' do
      result = described_class.new.deliver(to: '+920000000000', body: 'test message')

      expect(result).not_to be_success
      expect(result.error_code).to eq('undeliverable')
      expect(result.provider_reference).to be_nil
    end

    it 'never logs the message body' do
      allow(Rails.logger).to receive(:info)

      described_class.new.deliver(to: '+923001234567', body: 'secret-otp-body-123456')

      expect(Rails.logger).to have_received(:info) do |message|
        expect(message).not_to include('secret-otp-body-123456')
      end
    end
  end
end

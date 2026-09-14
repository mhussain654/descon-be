# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Providers::TwilioAdapter do
  let(:configuration) do
    instance_double(
      AiCalls::Configuration,
      twilio_account_sid: 'account-sid',
      twilio_auth_token: 'auth-token',
      twilio_base_url: 'https://api.twilio.com',
      twilio_open_timeout: 5,
      twilio_read_timeout: 10
    )
  end

  let(:adapter) { described_class.new(configuration:) }

  it 'reports availability only when both credentials are present' do
    expect(adapter.available?).to be(true)

    missing_token = instance_double(AiCalls::Configuration, twilio_account_sid: 'account-sid', twilio_auth_token: nil)
    expect(described_class.new(configuration: missing_token).available?).to be(false)

    missing_sid = instance_double(AiCalls::Configuration, twilio_account_sid: nil, twilio_auth_token: 'auth-token')
    expect(described_class.new(configuration: missing_sid).available?).to be(false)
  end

  describe '#fetch_call' do
    it 'returns the raw parsed call resource' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return({
        sid: 'CA-call-sid', status: 'completed', price: '-0.0150', price_unit: 'USD'
      }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect(adapter.fetch_call(call_sid: 'CA-call-sid')).to eq(
        'sid' => 'CA-call-sid', 'status' => 'completed', 'price' => '-0.0150', 'price_unit' => 'USD'
      )
    end

    it 'raises when the provider is not configured' do
      unavailable = described_class.new(
        configuration: instance_double(AiCalls::Configuration, twilio_account_sid: nil, twilio_auth_token: nil)
      )

      expect { unavailable.fetch_call(call_sid: 'CA-call-sid') }.to raise_error(AiCallProviderUnavailableError)
    end

    it 'raises a provider request error on a non-success response' do
      response = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
      allow(response).to receive(:body).and_return({ message: 'not found' }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect { adapter.fetch_call(call_sid: 'missing') }.to raise_error(AiCallProviderRequestError)
    end

    it 'raises a provider request error on invalid json or a network failure' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('not-json')
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect { adapter.fetch_call(call_sid: 'CA-call-sid') }.to raise_error(AiCallProviderRequestError)

      allow(Net::HTTP).to receive(:start).and_raise(SocketError)

      expect { adapter.fetch_call(call_sid: 'CA-call-sid') }.to raise_error(AiCallProviderRequestError)
    end
  end

  describe '#fetch_call_cost' do
    it 'derives price and price_unit from the call resource' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return({ price: '-0.0150', price_unit: 'USD' }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect(adapter.fetch_call_cost(call_sid: 'CA-call-sid')).to eq(price: '-0.0150', price_unit: 'USD')
    end
  end
end

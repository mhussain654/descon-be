# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sms::Providers::SendpkProvider do
  let(:configuration) do
    instance_double(
      Sms::Configuration,
      sendpk_api_key: 'api-key-1',
      sendpk_sender_id: 'DESCON',
      sendpk_base_url: 'https://sendpk.com',
      sendpk_open_timeout: 5,
      sendpk_read_timeout: 10
    )
  end

  let(:provider) { described_class.new(configuration:) }

  def stub_response(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return(body)
    allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))
  end

  it 'sends api_key as a POST body field, never in the URL query string' do
    captured_request = nil
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return('OK ID:1')
    allow(Net::HTTP).to receive(:start) do |host, _port, **kwargs, &block|
      expect(host).to eq('sendpk.com')
      expect(kwargs[:use_ssl]).to be(true)
      http = instance_double(Net::HTTP, request: response)
      allow(http).to receive(:request) { |request| captured_request = request }.and_return(response)
      block.call(http)
    end

    provider.deliver(to: '+923001234567', body: 'your code is 123456')

    expect(captured_request.uri.query).to be_nil
    expect(captured_request.body).to include('api_key=api-key-1')
    expect(captured_request.body).to include('sender=DESCON')
    expect(captured_request.body).to include('mobile=%2B923001234567')
  end

  it 'reports success and the provider message id for an "OK ID:<id>" response' do
    stub_response('OK ID:29346')

    result = provider.deliver(to: '+923001234567', body: 'your code is 123456')

    expect(result).to be_success
    expect(result.provider_reference).to eq('29346')
  end

  it 'maps a documented failure code to a descriptive error_code' do
    stub_response('4')

    result = provider.deliver(to: '+923001234567', body: 'your code is 123456')

    expect(result).not_to be_success
    expect(result.error_code).to eq('missing_sender_id')
  end

  it 'reports an unknown_error for a response that matches neither shape' do
    stub_response('<html>unexpected</html>')

    result = provider.deliver(to: '+923001234567', body: 'your code is 123456')

    expect(result).not_to be_success
    expect(result.error_code).to eq('unknown_error')
  end

  it 'never calls the network when the sender id is not configured' do
    unconfigured = instance_double(Sms::Configuration, sendpk_api_key: 'api-key-1', sendpk_sender_id: nil)
    allow(Net::HTTP).to receive(:start)

    result = described_class.new(configuration: unconfigured).deliver(to: '+923001234567', body: 'code')

    expect(result).not_to be_success
    expect(result.error_code).to eq('not_configured')
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'never calls the network when the api key is not configured' do
    unconfigured = instance_double(Sms::Configuration, sendpk_api_key: nil, sendpk_sender_id: 'DESCON')
    allow(Net::HTTP).to receive(:start)

    result = described_class.new(configuration: unconfigured).deliver(to: '+923001234567', body: 'code')

    expect(result).not_to be_success
    expect(result.error_code).to eq('not_configured')
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'reports a timeout distinctly from a general network error' do
    allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)

    result = provider.deliver(to: '+923001234567', body: 'code')

    expect(result).not_to be_success
    expect(result.error_code).to eq('timeout')
  end

  it 'reports a network_error for a connection failure' do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError)

    result = provider.deliver(to: '+923001234567', body: 'code')

    expect(result).not_to be_success
    expect(result.error_code).to eq('network_error')
  end
end

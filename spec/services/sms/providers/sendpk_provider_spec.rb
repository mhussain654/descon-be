# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sms::Providers::SendpkProvider do
  let(:configuration) do
    instance_double(
      Sms::Configuration,
      sendpk_api_key: 'api-key-1',
      sendpk_sender_id: 'DESCON',
      sendpk_template_id: '10743',
      sendpk_base_url: 'https://sendpk.com',
      sendpk_open_timeout: 5,
      sendpk_read_timeout: 10
    )
  end

  let(:provider) { described_class.new(configuration:) }

  def query_params(request)
    URI.decode_www_form(request.path.split('?', 2).last.to_s).to_h
  end

  def stub_response(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return(body)
    allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))
  end

  it 'sends a GET request with the credentials as query parameters over https' do
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

    provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

    expect(captured_request).to be_a(Net::HTTP::Get)
    query = captured_request.path
    expect(query).to include('api_key=api-key-1', 'sender=DESCON', 'mobile=%2B923001234567')
  end

  it 'sends the approved template id and the variables as a JSON message, never free text' do
    captured_request = nil
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return('OK ID:1')
    allow(Net::HTTP).to receive(:start) do |*, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { |request| captured_request = request }.and_return(response)
      block.call(http)
    end

    provider.deliver(to: '923001234567', body: 'ignored free text', variables: { code: '482731', minutes: 5 })

    form = query_params(captured_request)
    expect(form['template_id']).to eq('10743')
    expect(JSON.parse(form['message'])).to eq('code' => '482731', 'minutes' => '5')
    expect(captured_request.path).not_to include('ignored')
  end

  it 'marks Urdu sends as unicode and leaves English sends untyped' do
    types = []
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return('OK ID:1')
    allow(Net::HTTP).to receive(:start) do |*, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { |request|
        types << query_params(request)['type']
      }.and_return(response)
      block.call(http)
    end

    provider.deliver(to: '923001234567', variables: { code: '1', minutes: 5 }, locale: 'ur')
    provider.deliver(to: '923001234567', variables: { code: '1', minutes: 5 }, locale: 'en')

    expect(types).to eq(['unicode', nil])
  end

  it 'sends the Urdu template id for an Urdu locale and the default one otherwise' do
    seen = []
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return('OK ID:1')
    allow(Net::HTTP).to receive(:start) do |*, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { |request|
        seen << query_params(request)['template_id']
      }.and_return(response)
      block.call(http)
    end
    allow(configuration).to receive(:sendpk_template_id) { |locale| locale == 'ur' ? '10791' : '10790' }

    provider.deliver(to: '923001234567', variables: { code: '1', minutes: 5 }, locale: 'ur')
    provider.deliver(to: '923001234567', variables: { code: '1', minutes: 5 }, locale: 'en')

    expect(seen).to eq(%w[10791 10790])
  end

  it 'reports success and the provider message id for an "OK ID:<id>" response' do
    stub_response('OK ID:29346')

    result = provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

    expect(result).to be_success
    expect(result.provider_reference).to eq('29346')
  end

  it 'maps a documented failure code to a descriptive error_code' do
    stub_response('4')

    result = provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

    expect(result).not_to be_success
    expect(result.error_code).to eq('missing_sender_id')
  end

  it 'reports an unknown_error for a response that matches neither shape' do
    stub_response('<html>unexpected</html>')

    result = provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

    expect(result).not_to be_success
    expect(result.error_code).to eq('unknown_error')
  end

  it 'never calls the network when the sender id is not configured' do
    unconfigured = instance_double(Sms::Configuration, sendpk_api_key: 'api-key-1', sendpk_sender_id: nil,
                                                       sendpk_template_id: '10743')
    allow(Net::HTTP).to receive(:start)

    result = described_class.new(configuration: unconfigured).deliver(to: '+923001234567',
                                                                      variables: {
                                                                        code: '123456', minutes: 5
                                                                      })

    expect(result).not_to be_success
    expect(result.error_code).to eq('not_configured')
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'never calls the network when the template id is not configured' do
    unconfigured = instance_double(
      Sms::Configuration, sendpk_api_key: 'api-key-1', sendpk_sender_id: 'DESCON', sendpk_template_id: nil
    )
    allow(Net::HTTP).to receive(:start)

    result = described_class.new(configuration: unconfigured).deliver(
      to: '+923001234567', variables: { code: '123456', minutes: 5 }
    )

    expect(result.error_code).to eq('not_configured')
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'never calls the network when the api key is not configured' do
    unconfigured = instance_double(Sms::Configuration, sendpk_api_key: nil, sendpk_sender_id: 'DESCON',
                                                       sendpk_template_id: '10743')
    allow(Net::HTTP).to receive(:start)

    result = described_class.new(configuration: unconfigured).deliver(to: '+923001234567',
                                                                      variables: {
                                                                        code: '123456', minutes: 5
                                                                      })

    expect(result).not_to be_success
    expect(result.error_code).to eq('not_configured')
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'reports a timeout distinctly from a general network error' do
    allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)

    result = provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

    expect(result).not_to be_success
    expect(result.error_code).to eq('timeout')
  end

  it 'reports a network_error for a connection failure' do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError)

    result = provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

    expect(result).not_to be_success
    expect(result.error_code).to eq('network_error')
  end

  describe 'HTTPS enforcement' do
    it 'rejects an HTTP base URL outside test, without ever calling the network' do
      allow(Rails.env).to receive(:test?).and_return(false)
      insecure_configuration = instance_double(
        Sms::Configuration,
        sendpk_api_key: 'api-key-1', sendpk_sender_id: 'DESCON', sendpk_template_id: '10743', sendpk_base_url: 'http://sendpk.com',
        sendpk_open_timeout: 5, sendpk_read_timeout: 10
      )
      allow(Net::HTTP).to receive(:start)

      result = described_class.new(configuration: insecure_configuration).deliver(to: '+923001234567',
                                                                                  variables: {
                                                                                    code: '123456', minutes: 5
                                                                                  })

      expect(result).not_to be_success
      expect(result.error_code).to eq('insecure_endpoint_rejected')
      expect(Net::HTTP).not_to have_received(:start)
    end

    it 'allows an HTTP base URL in test (a local stub has no real certificate to present)' do
      insecure_configuration = instance_double(
        Sms::Configuration,
        sendpk_api_key: 'api-key-1', sendpk_sender_id: 'DESCON', sendpk_template_id: '10743', sendpk_base_url: 'http://sendpk.com',
        sendpk_open_timeout: 5, sendpk_read_timeout: 10
      )
      stub_response('OK ID:1')

      result = described_class.new(configuration: insecure_configuration).deliver(to: '+923001234567',
                                                                                  variables: {
                                                                                    code: '123456', minutes: 5
                                                                                  })

      expect(result).to be_success
    end
  end

  describe 'HTTP status handling' do
    it 'never treats a non-2xx response as delivered, even if its body matches the success pattern' do
      response = Net::HTTPInternalServerError.new('1.1', '500', 'Internal Server Error')
      allow(response).to receive(:body).and_return('OK ID:1')
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      result = provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

      expect(result).not_to be_success
      expect(result.error_code).to eq('http_error')
    end

    it 'maps a 3xx redirect to its own error code rather than silently following or misparsing it' do
      response = Net::HTTPFound.new('1.1', '302', 'Found')
      allow(response).to receive(:body).and_return('')
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      result = provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

      expect(result).not_to be_success
      expect(result.error_code).to eq('unexpected_redirect')
    end

    it 'still parses a documented failure code normally on a 200 response' do
      stub_response('4')

      result = provider.deliver(to: '+923001234567', variables: { code: '123456', minutes: 5 })

      expect(result).not_to be_success
      expect(result.error_code).to eq('missing_sender_id')
    end
  end
end

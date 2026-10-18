# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Providers::RobocallAdapter do
  let(:api_key) { 'super-secret-robocall-key' }
  let(:configuration) do
    instance_double(AiCalls::RobocallConfiguration, api_key:, base_url: 'https://corporate.robocall.pk',
                                                    open_timeout: 5, read_timeout: 10)
  end
  let(:adapter) { described_class.new(configuration:) }
  let(:requests) { [] }

  def build_response(body, response_class, http_code)
    response_class.new('1.1', http_code, 'status').tap do |response|
      allow(response).to receive(:body).and_return(body.is_a?(String) ? body : body.to_json)
    end
  end

  # `fields` is the JSON body when no explicit body is given, so examples can
  # write `stub_response(data: { ... })`.
  def stub_response(body = nil, response_class: Net::HTTPOK, http_code: '200', **fields)
    response = build_response(body || fields, response_class, http_code)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) { |request| response.tap { requests << request } }
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  def requested_query = Rack::Utils.parse_query(requests.last.uri.query)

  describe '#available?' do
    it 'is true only when an api key is configured' do
      expect(adapter).to be_available
      expect(described_class.new(configuration: instance_double(AiCalls::RobocallConfiguration, api_key: nil)))
        .not_to be_available
    end
  end

  describe '#initiate_call' do
    it 'sends only the number (digits only) and the voice id, with the api key, and returns the call id' do
      stub_response(status: 200, message: 'ok', data: { call_id: 20_076, call_to: '923001234567', voice_id: '102' })

      result = adapter.initiate_call(voice_id: '102', to_number: '+923001234567')

      expect(result.call_id).to eq('20076')
      expect(requests.last.path).to start_with('/api/calls?')
      expect(requested_query).to eq('api_key' => api_key, 'caller_id' => '923001234567', 'voice_id' => '102')
    end

    it 'reads the call id from order_id when the response uses RoboCall\'s portal sample shape' do
      stub_response(status: 200, message: 'Call placed successfully', data: { order_id: 1, order_num: '1001' })

      expect(adapter.initiate_call(voice_id: '102', to_number: '923001234567').call_id).to eq('1')
    end

    it 'raises when RoboCall reports a non-200 status inside a successful HTTP response' do
      stub_response(status: 422, message: 'Invalid parameter values')

      expect { adapter.initiate_call(voice_id: '102', to_number: '923001234567') }
        .to raise_error(AiCallProviderRequestError)
    end

    it 'returns a blank call id when the provider answers without one' do
      stub_response(status: 200, message: 'queued', data: {})

      expect(adapter.initiate_call(voice_id: '102', to_number: '923001234567').call_id).to be_nil
    end

    it 'raises AiCallProviderUnavailableError without any request when no key is configured' do
      keyless = described_class.new(configuration: instance_double(AiCalls::RobocallConfiguration, api_key: nil))
      allow(Net::HTTP).to receive(:start)

      expect { keyless.initiate_call(voice_id: '102', to_number: '923001234567') }
        .to raise_error(AiCallProviderUnavailableError)
      expect(Net::HTTP).not_to have_received(:start)
    end

    it 'raises AiCallProviderRequestError on a non-success response, never leaking the key' do
      stub_response({ message: "bad #{api_key}" }, response_class: Net::HTTPForbidden, http_code: '403')

      expect { adapter.initiate_call(voice_id: '102', to_number: '923001234567') }
        .to raise_error(AiCallProviderRequestError) { |error| expect(error.message).not_to include(api_key) }
    end

    it 'raises AiCallProviderRequestError on unreadable JSON and on network failures' do
      stub_response('<html>not json</html>')
      expect { adapter.initiate_call(voice_id: '102', to_number: '923001234567') }
        .to raise_error(AiCallProviderRequestError)

      allow(Net::HTTP).to receive(:start).and_raise(SocketError, "could not reach host?api_key=#{api_key}")
      expect { adapter.initiate_call(voice_id: '102', to_number: '923001234567') }
        .to raise_error(AiCallProviderRequestError) { |error| expect(error.message).not_to include(api_key) }
    end

    it 'raises AiCallProviderRequestError when the body is not a JSON object' do
      stub_response('[1, 2]')

      expect { adapter.initiate_call(voice_id: '102', to_number: '923001234567') }
        .to raise_error(AiCallProviderRequestError)
    end
  end

  describe '#initiate_multiple_calls_raw' do
    it 'sends every number comma-separated to the multiple-calls endpoint and returns the response untouched' do
      stub_response(status: 200, message: 'Call placed successfully', data: [{ call_id: 1 }, { call_id: 2 }])

      body = adapter.initiate_multiple_calls_raw(voice_id: '102', to_numbers: ['+923001234567', '03007654321'])

      expect(body.dig('data', 1, 'call_id')).to eq(2)
      expect(requests.last.path).to start_with('/api/mutliple_calls?')
      expect(requested_query).to eq('api_key' => api_key, 'caller_id' => '923001234567,03007654321',
                                    'voice_id' => '102')
    end
  end

  describe '#fetch_call' do
    it 'returns the numeric status code and the key the candidate pressed' do
      stub_response(code: 200, data: { call_id: 20_076, call_status: '2', dtmf: '3' })

      status = adapter.fetch_call(call_id: '20076')

      expect(status.status_code).to eq(2)
      expect(status.dtmf).to eq('3')
      expect(requests.last.path).to start_with('/api/get_call?')
      expect(requested_query).to eq('api_key' => api_key, 'call_id' => '20076')
    end

    it 'returns nil fields for an unreadable status or a missing data section' do
      stub_response(data: { call_status: 'weird', dtmf: '' })
      expect(adapter.fetch_call(call_id: '1').to_h).to eq(status_code: nil, dtmf: nil)

      stub_response(code: 200)
      expect(adapter.fetch_call(call_id: '1').to_h).to eq(status_code: nil, dtmf: nil)
    end
  end

  describe '#verify_key and #check_balance' do
    it 'call their own endpoints and return the parsed response' do
      stub_response(status: 200, valid: true, message: 'ok')
      expect(adapter.verify_key).to include('valid' => true)
      expect(requests.last.path).to start_with('/api/verify-key?')

      stub_response(data: { balance: '1500', username: 'descon', call_rate: '2' })
      expect(adapter.check_balance.dig('data', 'balance')).to eq('1500')
      expect(requests.last.path).to start_with('/api/check_balance?')
    end
  end
end

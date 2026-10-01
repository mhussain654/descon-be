# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Providers::ElevenlabsAdapter do
  let(:configuration) do
    instance_double(
      AiCalls::Configuration,
      elevenlabs_api_key: 'elevenlabs-key',
      elevenlabs_base_url: 'https://api.elevenlabs.io',
      elevenlabs_webhook_signing_secret: 'webhook-secret',
      elevenlabs_open_timeout: 5,
      elevenlabs_read_timeout: 15
    )
  end

  let(:adapter) { described_class.new(configuration:) }

  def outbound_call_request
    AiCalls::Providers::OutboundCallRequest.new(
      agent_id: 'agent-1',
      agent_phone_number_id: 'phone-1',
      to_number: '+923001234567',
      dynamic_variables: { candidate_name: 'Ali' },
      conversation_config_override: {},
      recording_enabled: false
    )
  end

  it 'reports availability only when an api key is configured' do
    expect(adapter.available?).to be(true)

    missing_key = instance_double(AiCalls::Configuration, elevenlabs_api_key: nil)
    expect(described_class.new(configuration: missing_key).available?).to be(false)
  end

  describe '#initiate_outbound_call' do
    it 'originates a call and returns the provider identifiers' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return({
        conversation_id: 'conversation-1',
        callSid: 'CA-call-sid'
      }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(response)

      result = adapter.initiate_outbound_call(outbound_call_request)

      expect(result).to be_a(AiCalls::Providers::OutboundCallResult)
      expect(result.conversation_id).to eq('conversation-1')
      expect(result.twilio_call_sid).to eq('CA-call-sid')
    end

    it 'falls back to a snake_case call sid key' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return({ conversation_id: 'conversation-1', call_sid: 'CA-2' }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(response)

      result = adapter.initiate_outbound_call(outbound_call_request)

      expect(result.twilio_call_sid).to eq('CA-2')
    end

    it 'raises when the provider is not configured' do
      unavailable = described_class.new(configuration: instance_double(AiCalls::Configuration, elevenlabs_api_key: nil))

      expect do
        unavailable.initiate_outbound_call(outbound_call_request)
      end.to raise_error(AiCallProviderUnavailableError)
    end

    it 'raises a provider request error on a non-success response' do
      response = Net::HTTPBadRequest.new('1.1', '400', 'Bad Request')
      allow(response).to receive(:body).and_return({ error: 'invalid' }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect do
        adapter.initiate_outbound_call(outbound_call_request)
      end.to raise_error(AiCallProviderRequestError)
    end

    it 'raises a provider request error on invalid json or a network failure' do
      invalid_json = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(invalid_json).to receive(:body).and_return('not-json')
      allow(Net::HTTP).to receive(:start).and_return(invalid_json)

      expect do
        adapter.fetch_conversation(conversation_id: 'conversation-1')
      end.to raise_error(AiCallProviderRequestError)

      allow(Net::HTTP).to receive(:start).and_raise(Timeout::Error)

      expect do
        adapter.fetch_conversation(conversation_id: 'conversation-1')
      end.to raise_error(AiCallProviderRequestError)
    end
  end

  describe '#fetch_conversation' do
    it 'returns the raw parsed response body' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return({ status: 'done', analysis: { call_resolved: true } }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect(adapter.fetch_conversation(conversation_id: 'conversation-1')).to eq(
        'status' => 'done', 'analysis' => { 'call_resolved' => true }
      )
    end
  end

  describe '#fetch_agent_config and #update_agent_config' do
    it 'fetches and updates the published agent configuration' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return({ agent_id: 'agent-1', name: 'Descon Helpline' }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect(adapter.fetch_agent_config(agent_id: 'agent-1'))
        .to eq('agent_id' => 'agent-1', 'name' => 'Descon Helpline')
      expect(adapter.update_agent_config(agent_id: 'agent-1', config: { name: 'Updated' }))
        .to eq('agent_id' => 'agent-1', 'name' => 'Descon Helpline')
    end
  end

  describe '#verify_webhook_signature!' do
    let(:raw_body) { '{"event":"post_call_transcription"}' }

    def signed_header(timestamp:, body:, secret: 'webhook-secret')
      signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")
      "t=#{timestamp},v0=#{signature}"
    end

    it 'accepts a header with a valid, current signature' do
      travel_to(Time.zone.parse('2026-09-10T12:00:00Z')) do
        header = signed_header(timestamp: Time.current.to_i, body: raw_body)

        expect { adapter.verify_webhook_signature!(header:, raw_body:) }.not_to raise_error
      end
    end

    it 'rejects a header with an incorrect signature' do
      header = "t=#{Time.current.to_i},v0=#{'0' * 64}"

      expect { adapter.verify_webhook_signature!(header:, raw_body:) }.to raise_error(AiCallSignatureInvalidError)
    end

    it 'rejects a signature computed with the wrong secret' do
      header = signed_header(timestamp: Time.current.to_i, body: raw_body, secret: 'wrong-secret')

      expect { adapter.verify_webhook_signature!(header:, raw_body:) }.to raise_error(AiCallSignatureInvalidError)
    end

    it 'rejects a timestamp outside the replay-tolerance window' do
      travel_to(Time.zone.parse('2026-09-10T12:00:00Z')) do
        stale_timestamp = 31.minutes.ago.to_i
        header = signed_header(timestamp: stale_timestamp, body: raw_body)

        expect { adapter.verify_webhook_signature!(header:, raw_body:) }.to raise_error(AiCallSignatureInvalidError)
      end
    end

    it 'rejects a malformed signature header' do
      expect do
        adapter.verify_webhook_signature!(header: 'not-a-valid-header', raw_body:)
      end.to raise_error(AiCallSignatureInvalidError)

      expect { adapter.verify_webhook_signature!(header: nil, raw_body:) }.to raise_error(AiCallSignatureInvalidError)
    end
  end
end

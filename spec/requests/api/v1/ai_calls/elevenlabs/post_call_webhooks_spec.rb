# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 AI Calls ElevenLabs Post Call Webhooks', type: :request do
  around do |example|
    original_env = ENV.to_h
    ENV['ELEVENLABS_WEBHOOK_SIGNING_SECRET'] = 'webhook-secret'
    example.run
  ensure
    ENV.replace(original_env)
  end

  def signed_header(body:, timestamp: Time.current.to_i, secret: 'webhook-secret')
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")
    "t=#{timestamp},v0=#{signature}"
  end

  def payload_for(conversation_id)
    { data: payload_data(conversation_id) }.to_json
  end

  def payload_data(conversation_id)
    {
      conversation_id:,
      metadata: { call_duration_secs: 30 },
      analysis: { data_collection_results: extraction_results },
      transcript: [{ role: 'agent', message: 'Hello.' }]
    }
  end

  def extraction_results
    { human_answered: true, call_resolved: true, callback_requested: false, escalation_requested: false }
  end

  it 'applies a validly signed post-call webhook and updates the call' do
    call_record = create(:candidate_ai_call, status: 'queued', elevenlabs_conversation_id: 'conversation-1')
    body = payload_for('conversation-1')

    post '/api/v1/ai_calls/elevenlabs/webhooks/post_call',
         params: body,
         headers: { 'Content-Type' => 'application/json', 'ElevenLabs-Signature' => signed_header(body:) }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'status')).to eq('completed')
    expect(call_record.reload.outcome).to eq('answered')
    expect(call_record.candidate_ai_call_transcript.transcript).to eq('Hello.')
  end

  it 'rejects a request with an invalid signature' do
    create(:candidate_ai_call, status: 'queued', elevenlabs_conversation_id: 'conversation-1')
    body = payload_for('conversation-1')

    post '/api/v1/ai_calls/elevenlabs/webhooks/post_call',
         params: body,
         headers: { 'Content-Type' => 'application/json', 'ElevenLabs-Signature' => "t=1,v0=#{'0' * 64}" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('ai_call_signature_invalid')
  end

  it 'returns 404 when no call matches the conversation_id' do
    body = payload_for('unknown-conversation')

    post '/api/v1/ai_calls/elevenlabs/webhooks/post_call',
         params: body,
         headers: { 'Content-Type' => 'application/json', 'ElevenLabs-Signature' => signed_header(body:) }

    expect(response).to have_http_status(:not_found)
  end

  it 'is idempotent -- a replayed delivery does not error and does not duplicate the event' do
    call_record = create(:candidate_ai_call, status: 'queued', elevenlabs_conversation_id: 'conversation-1')
    body = payload_for('conversation-1')
    headers = { 'Content-Type' => 'application/json', 'ElevenLabs-Signature' => signed_header(body:) }

    post '/api/v1/ai_calls/elevenlabs/webhooks/post_call', params: body, headers: headers
    post '/api/v1/ai_calls/elevenlabs/webhooks/post_call', params: body, headers: headers

    expect(response).to have_http_status(:ok)
    expect(call_record.candidate_ai_call_events.count).to eq(1)
  end
end

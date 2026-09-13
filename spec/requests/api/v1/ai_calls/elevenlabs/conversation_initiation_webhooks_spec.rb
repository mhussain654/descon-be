# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 AI Calls ElevenLabs Conversation Initiation Webhooks', type: :request do
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

  it 'creates a CandidateAiCall for a validly signed inbound call' do
    body = { data: { conversation_id: 'conversation-1', caller_id: '+920000000000' } }.to_json

    post '/api/v1/ai_calls/elevenlabs/webhooks/conversation_initiation',
         params: body,
         headers: { 'Content-Type' => 'application/json', 'ElevenLabs-Signature' => signed_header(body:) }

    expect(response).to have_http_status(:ok)
    expect(CandidateAiCall.find_by(elevenlabs_conversation_id: 'conversation-1')).to be_present
  end

  it 'rejects a request with an invalid signature' do
    body = { data: { conversation_id: 'conversation-1', caller_id: '+920000000000' } }.to_json

    post '/api/v1/ai_calls/elevenlabs/webhooks/conversation_initiation',
         params: body,
         headers: { 'Content-Type' => 'application/json', 'ElevenLabs-Signature' => "t=1,v0=#{'0' * 64}" }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'is idempotent across a redelivered webhook' do
    body = { data: { conversation_id: 'conversation-2', caller_id: '+920000000000' } }.to_json
    headers = { 'Content-Type' => 'application/json', 'ElevenLabs-Signature' => signed_header(body:) }

    post '/api/v1/ai_calls/elevenlabs/webhooks/conversation_initiation', params: body, headers: headers
    post '/api/v1/ai_calls/elevenlabs/webhooks/conversation_initiation', params: body, headers: headers

    expect(response).to have_http_status(:ok)
    expect(CandidateAiCall.where(elevenlabs_conversation_id: 'conversation-2').count).to eq(1)
  end
end

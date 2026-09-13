# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 AI Calls ElevenLabs Tool Calls', type: :request do
  around do |example|
    original_env = ENV.to_h
    ENV['AI_CALLS_TOOL_SHARED_SECRET'] = 'tool-secret'
    example.run
  ensure
    ENV.replace(original_env)
  end

  let(:call_record) { create(:candidate_ai_call, :inbound, elevenlabs_conversation_id: 'conversation-1') }
  let(:valid_headers) { { 'X-AI-Calls-Tool-Secret' => 'tool-secret' } }

  def call_tool(tool_name, conversation_id: 'conversation-1', params: {}, headers: valid_headers)
    post "/api/v1/ai_calls/elevenlabs/tools/#{tool_name}",
         params: params.merge(conversation_id:), headers: headers
  end

  describe 'shared-secret authentication' do
    it 'rejects a request with a missing secret header' do
      call_tool('create_callback_request', headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a request with an invalid secret' do
      call_tool('create_callback_request', headers: { 'X-AI-Calls-Tool-Secret' => 'wrong-secret' })

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a request when no secret is configured' do
      ENV.delete('AI_CALLS_TOOL_SHARED_SECRET')

      call_tool('create_callback_request')

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'unknown tool_name' do
    it 'returns 404' do
      call_tool('not_a_real_tool')

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'routing' do
    it 'does not allow GET' do
      call_record
      get '/api/v1/ai_calls/elevenlabs/tools/create_callback_request',
          params: { conversation_id: 'conversation-1' }, headers: valid_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'dispatching to a registered tool' do
    it 'dispatches create_callback_request and returns its result' do
      call_record
      call_tool('create_callback_request', params: { reason: 'ring me tonight' })

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['data']).to eq('callback_requested' => true, 'reason' => 'ring me tonight')
      expect(call_record.reload.callback_requested_at).to be_present
    end

    it 'dispatches transfer_to_human and returns its result' do
      call_record
      call_tool('transfer_to_human', params: { reason: 'wants a human' })

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['data']).to eq(
        'transfer_available' => false, 'callback_requested' => true, 'reason' => 'wants a human'
      )
    end

    it 'refuses to reveal data for an unverified inbound call' do
      call_record
      call_tool('get_payment_status')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to eq('error' => 'not_verified')
    end
  end

  describe 'CandidateAiCallEvent recording' do
    it 'records one event per tool call, without deduping repeated identical calls' do
      call_record

      expect do
        call_tool('create_callback_request', params: { reason: 'first' })
        call_tool('create_callback_request', params: { reason: 'first' })
      end.to change { call_record.candidate_ai_call_events.count }.by(2)

      events = call_record.candidate_ai_call_events.where(event_type: 'create_callback_request')
      expect(events.pluck(:event_key).uniq.size).to eq(2)
    end
  end
end

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
    it 'records one event for a genuinely new tool call' do
      call_record
      call_tool('create_callback_request', params: { reason: 'first' })

      events = call_record.candidate_ai_call_events.where(event_type: 'create_callback_request')
      expect(events.count).to eq(1)
    end

    it 'is idempotent -- a replayed delivery with identical arguments does not re-run the handler' do
      call_record

      expect do
        call_tool('create_callback_request', params: { reason: 'first' })
        call_tool('create_callback_request', params: { reason: 'first' })
      end.to change { call_record.candidate_ai_call_events.count }.by(1)

      first_requested_at = call_record.reload.callback_requested_at
      call_tool('create_callback_request', params: { reason: 'first' })
      expect(call_record.reload.callback_requested_at).to eq(first_requested_at)
    end

    it 'records a distinct event when the same tool is called with different arguments' do
      call_record

      expect do
        call_tool('create_callback_request', params: { reason: 'first' })
        call_tool('create_callback_request', params: { reason: 'second' })
      end.to change { call_record.candidate_ai_call_events.count }.by(2)
    end

    it 'returns the first invocation result on a replayed delivery' do
      call_record
      call_tool('create_callback_request', params: { reason: 'first' })
      first_body = response.parsed_body

      call_tool('create_callback_request', params: { reason: 'first' })

      expect(response.parsed_body['data']).to eq(first_body['data'])
    end

    it 'does not re-increment verification_attempts when an identical verify_caller_identity call is replayed' do
      call_record

      call_tool('verify_caller_identity', params: { reference_number: 'unknown-ref' })
      call_tool('verify_caller_identity', params: { reference_number: 'unknown-ref' })

      expect(call_record.reload.verification_attempts).to eq(1)
    end

    it 'still counts a genuinely new verify_caller_identity attempt with different arguments' do
      call_record

      call_tool('verify_caller_identity', params: { reference_number: 'unknown-ref' })
      call_tool('verify_caller_identity', params: { reference_number: 'another-ref' })

      expect(call_record.reload.verification_attempts).to eq(2)
    end
  end
end

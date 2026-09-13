# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate AI Calls', type: :request do
  around do |example|
    original_env = ENV.to_h
    ENV['AI_VOICE_OUTBOUND_ENABLED'] = 'true'
    ENV['ELEVENLABS_API_KEY'] = 'elevenlabs-key'
    ENV['ELEVENLABS_OUTBOUND_AGENT_ID'] = 'agent-out-1'
    ENV['ELEVENLABS_AGENT_PHONE_NUMBER_ID'] = 'phone-1'
    ENV['AI_VOICE_CALLING_HOURS_START'] = '0'
    ENV['AI_VOICE_CALLING_HOURS_END'] = '24'
    example.run
  ensure
    ENV.replace(original_env)
  end

  before do
    ensure_staff_authorization_reference_data!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{login_as(user)}", 'Idempotency-Key' => SecureRandom.uuid }
  end

  def stub_successful_call
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({ conversation_id: 'conversation-1', callSid: 'CA-1' }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/ai_calls' do
    it 'triggers a call for an authorized admin' do
      stub_successful_call
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls",
           params: { candidate_ai_call: { call_reason: 'missing_documents' } }.to_json,
           headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'status')).to eq('queued')
      expect(response.parsed_body.dig('data', 'call_reason')).to eq('missing_documents')
    end

    it 'replays the same response for a retried Idempotency-Key without placing a second call' do
      stub_successful_call
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)
      headers = auth_headers(admin).merge('Content-Type' => 'application/json')
      body = { candidate_ai_call: { call_reason: 'missing_documents' } }.to_json

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", params: body, headers: headers
      first_id = response.parsed_body.dig('data', 'id')

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", params: body, headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'id')).to eq(first_id)
      expect(CandidateAiCall.count).to eq(1)
    end

    it 'requires an Idempotency-Key header' do
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls",
           params: { candidate_ai_call: { call_reason: 'missing_documents' } }.to_json,
           headers: { 'Authorization' => "Bearer #{login_as(admin)}", 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_idempotency_key')
    end

    it 'rejects an unknown call_reason' do
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls",
           params: { candidate_ai_call: { call_reason: 'bogus' } }.to_json,
           headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_ai_call.call_reason')
    end

    it 'forbids a staff member without trigger_ai_calls' do
      finance = create(:user, role: 'finance')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls",
           params: { candidate_ai_call: { call_reason: 'missing_documents' } }.to_json,
           headers: auth_headers(finance).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      candidate = create(:candidate)

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls",
           params: { candidate_ai_call: { call_reason: 'missing_documents' } }.to_json,
           headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 503 when outbound calling is disabled' do
      ENV['AI_VOICE_OUTBOUND_ENABLED'] = 'false'
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls",
           params: { candidate_ai_call: { call_reason: 'missing_documents' } }.to_json,
           headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('ai_call_outbound_disabled')
    end
  end

  describe 'GET /api/v1/admin/candidates/:candidate_id/ai_calls' do
    it "lists the candidate's admin-triggered call history, most recent first" do
      stub_successful_call
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls",
           params: { candidate_ai_call: { call_reason: 'missing_documents' } }.to_json,
           headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      get "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].size).to eq(1)
      expect(response.parsed_body.dig('data', 0, 'call_reason')).to eq('missing_documents')
    end

    it 'forbids a staff member without trigger_ai_calls' do
      finance = create(:user, role: 'finance')
      candidate = create(:candidate)

      get "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", headers: auth_headers(finance)

      expect(response).to have_http_status(:forbidden)
    end
  end
end

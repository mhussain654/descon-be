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

  # db:seed (run when CI prepares the test database) installs the starter call types for real.
  before do
    RobocallVoice.delete_all
    ensure_staff_authorization_reference_data!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{login_as(user)}", 'Idempotency-Key' => SecureRandom.uuid }
  end

  let(:voice) { create(:robocall_voice, name_en: 'Upload documents', voice_id: '538') }

  # RoboCall plays a recorded voice: only the voice id and the number are sent.
  def stub_successful_call
    ENV['AI_VOICE_PROVIDER'] = 'robocall'
    adapter = instance_double(AiCalls::Providers::RobocallAdapter)
    allow(AiCalls::Providers::RobocallAdapter).to receive(:new).and_return(adapter)
    allow(adapter).to receive(:initiate_call) do
      AiCalls::Providers::RobocallAdapter::CallResult.new(call_id: SecureRandom.hex(4))
    end
    adapter
  end

  def call_params(robocall_voice = voice)
    { candidate_ai_call: { robocall_voice_id: robocall_voice.public_id } }.to_json
  end

  def json_headers(user = nil)
    base = user ? auth_headers(user) : {}
    base.merge('Content-Type' => 'application/json')
  end

  def post_call(candidate, user, robocall_voice = voice)
    post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", params: call_params(robocall_voice),
                                                                     headers: json_headers(user)
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/ai_calls' do
    let(:admin) { create(:user, role: 'admin') }
    let(:candidate) { create(:candidate) }

    before { create(:candidate_assignment, candidate:) }

    it 'places a call with the chosen call type and names the voice in the response' do
      adapter = stub_successful_call

      post_call(candidate, admin)

      expect(response).to have_http_status(:created)
      expect(adapter).to have_received(:initiate_call).with(voice_id: '538', to_number: candidate.mobile_number)
      expect(response.parsed_body['data']).to include(
        'status' => 'queued', 'trigger' => 'manual', 'call_reason' => 'voice_call',
        'voice' => { 'voice_id' => '538', 'name_en' => 'Upload documents', 'name_ur' => voice.name_ur }
      )
    end

    it 'replays the same response for a retried Idempotency-Key without placing a second call' do
      stub_successful_call
      headers = json_headers(admin)

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", params: call_params, headers: headers
      first_id = response.parsed_body.dig('data', 'id')
      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", params: call_params, headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'id')).to eq(first_id)
      expect(CandidateAiCall.count).to eq(1)
    end

    it 'refuses the same call type again inside the cooldown but allows a different one' do
      stub_successful_call
      other = create(:robocall_voice, name_en: 'Medical report received', voice_id: '537')

      post_call(candidate, admin)
      post_call(candidate, admin)
      expect(response).to have_http_status(:too_many_requests)

      post_call(candidate, admin, other)
      expect(response).to have_http_status(:created)
    end

    it 'allows the same call type again once the cooldown has passed' do
      stub_successful_call
      post_call(candidate, admin)

      travel 16.minutes do
        post_call(candidate, admin)
      end

      expect(response).to have_http_status(:created)
    end

    it 'requires an Idempotency-Key header' do
      headers = { 'Authorization' => "Bearer #{login_as(admin)}", 'Content-Type' => 'application/json' }

      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", params: call_params, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_idempotency_key')
    end

    it 'rejects an unknown or switched-off call type' do
      stub_successful_call
      off = create(:robocall_voice, voice_id: '999', active: false)

      [off, instance_double(RobocallVoice, public_id: SecureRandom.uuid)].each do |bad|
        post_call(candidate, admin, bad)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_ai_call.robocall_voice_id')
      end
    end

    it 'forbids a staff member without trigger_ai_calls' do
      post_call(candidate, create(:user, role: 'finance'))

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      post "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", params: call_params, headers: json_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 503 when outbound calling is disabled' do
      ENV['AI_VOICE_OUTBOUND_ENABLED'] = 'false'
      stub_successful_call

      post_call(candidate, admin)

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('ai_call_outbound_disabled')
    end
  end

  describe 'GET /api/v1/admin/candidates/:candidate_id/ai_calls' do
    let(:admin) { create(:user, role: 'admin') }
    let(:candidate) { create(:candidate) }
    let(:assignment) { create(:candidate_assignment, candidate:) }

    def create_call(call_reason:, voice_id: nil, workflow_stage_code: nil, created_at: Time.current)
      communication = create(:communication, channel_code: 'ai_voice_call', direction_code: 'outbound',
                                             candidate_assignment: assignment)
      communication.create_candidate_ai_call!(
        candidate:, candidate_assignment: assignment, direction: 'outbound', call_reason:, workflow_stage_code:,
        provider_voice_id: voice_id, language_code: 'en', status: 'queued', verification_status: 'not_applicable',
        created_at:
      )
    end

    it 'lists every call the candidate had, newest first, saying what started it and which voice played' do
      voice
      create_call(call_reason: 'workflow_stage_notification', workflow_stage_code: 'documents_pending',
                  voice_id: '538', created_at: 3.hours.ago)
      create_call(call_reason: 'bulk_voice_call', voice_id: '538', created_at: 2.hours.ago)
      create_call(call_reason: 'voice_call', voice_id: '777', created_at: 1.hour.ago)

      get "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body['data']
      expect(rows.pluck('trigger')).to eq(%w[manual bulk automatic])
      expect(rows.last).to include('workflow_stage_code' => 'documents_pending')
      expect(rows.last['voice']).to include('voice_id' => '538', 'name_en' => 'Upload documents')
      expect(rows.first['voice']).to eq('voice_id' => '777', 'name_en' => nil, 'name_ur' => nil)
    end

    it "does not list another candidate's calls or inbound calls" do
      other = create(:candidate)
      other_assignment = create(:candidate_assignment, candidate: other)
      communication = create(:communication, channel_code: 'ai_voice_call', direction_code: 'outbound',
                                             candidate_assignment: other_assignment)
      communication.create_candidate_ai_call!(
        candidate: other, candidate_assignment: other_assignment, direction: 'outbound', call_reason: 'voice_call',
        language_code: 'en', status: 'queued', verification_status: 'not_applicable'
      )
      assignment

      get "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", headers: auth_headers(admin)

      expect(response.parsed_body['data']).to eq([])
    end

    it 'forbids a staff member without trigger_ai_calls' do
      finance = create(:user, role: 'finance')

      get "/api/v1/admin/candidates/#{candidate.public_id}/ai_calls", headers: auth_headers(finance)

      expect(response).to have_http_status(:forbidden)
    end
  end
end

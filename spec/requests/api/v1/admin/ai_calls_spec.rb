# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin AI Calls', type: :request do
  before do
    ensure_staff_authorization_reference_data!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{login_as(user)}" }
  end

  def needs_review_call
    communication = create(:communication, channel_code: 'ai_voice_call', direction_code: 'inbound')
    communication.create_candidate_ai_call!(
      direction: 'inbound', call_reason: 'general_helpline', language_code: 'en', status: 'completed',
      verification_status: 'pending', outcome: nil, outcome_reason: 'needs_manual_review'
    )
  end

  def resolved_call
    communication = create(:communication, channel_code: 'ai_voice_call', direction_code: 'outbound')
    communication.create_candidate_ai_call!(
      direction: 'outbound', call_reason: 'missing_documents', language_code: 'en', status: 'completed',
      verification_status: 'not_applicable', outcome: 'answered', outcome_reason: 'resolved'
    )
  end

  describe 'GET /api/v1/admin/ai_calls' do
    it 'defaults to the awaiting-review queue' do
      admin = create(:user, role: 'admin')
      awaiting = needs_review_call
      resolved_call

      get '/api/v1/admin/ai_calls', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to eq([awaiting.public_id])
      expect(response.parsed_body.dig('meta', 'applied_filters')).to eq('awaiting_review' => true)
    end

    it 'lists every call when filter[awaiting_review]=false' do
      admin = create(:user, role: 'admin')
      awaiting = needs_review_call
      resolved = resolved_call

      get '/api/v1/admin/ai_calls', params: { filter: { awaiting_review: 'false' } }, headers: auth_headers(admin)

      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to contain_exactly(awaiting.public_id, resolved.public_id)
    end

    it 'forbids a staff member without trigger_ai_calls' do
      finance = create(:user, role: 'finance')

      get '/api/v1/admin/ai_calls', headers: auth_headers(finance)

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/ai_calls'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/admin/ai_calls/:id' do
    it 'returns the call detail, including summary and review state' do
      admin = create(:user, role: 'admin')
      call_record = resolved_call
      call_record.update!(summary: 'Candidate confirmed receipt of documents.')

      get "/api/v1/admin/ai_calls/#{call_record.public_id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'summary')).to eq('Candidate confirmed receipt of documents.')
      expect(response.parsed_body.dig('data', 'outcome')).to eq('answered')
    end

    # Scoped (Admin::CandidateAiCallPolicy::Scope) before authorized, same
    # IDOR-safe pattern used elsewhere in this codebase -- an unauthorized
    # staff member gets 404, not 403, so a forbidden lookup never confirms
    # whether the record exists.
    it 'returns 404 (not 403) for a staff member without trigger_ai_calls' do
      finance = create(:user, role: 'finance')
      call_record = needs_review_call

      get "/api/v1/admin/ai_calls/#{call_record.public_id}", headers: auth_headers(finance)

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for an unknown call' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/ai_calls/unknown-id', headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end
  end
end

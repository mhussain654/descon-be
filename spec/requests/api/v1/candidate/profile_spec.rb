# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Profile', type: :request do
  before do
    ensure_canonical_workflow_stages!
  end

  def candidate_access_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  describe 'GET /api/v1/candidate/profile' do
    it 'returns only the authenticated candidate profile with masked sensitive data' do
      candidate = create(:candidate, cnic: '42101-1234567-1', preferred_locale: 'ur', status_code: 'registered')
      create(:candidate_assignment, candidate:, reference_number: 'DES-000111')

      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.headers['ETag']).to be_present
      expect(response.parsed_body.dig('data', 'id')).to eq(candidate.public_id)
      expect(response.parsed_body.dig('data', 'masked_cnic')).to eq('42101-*******-1')
      expect(response.parsed_body.dig('data', 'reference_number')).to eq('DES-000111')
      expect(response.parsed_body.dig('data', 'candidate_status')).to eq('registered')
      expect(response.parsed_body.dig('data', 'current_workflow_stage', 'code')).to eq('registered')
      expect(response.parsed_body.dig('data', 'payment', 'required_stage_code')).to eq('fee_pending')
      expect(response.parsed_body.dig('data', 'payment', 'blocking_reasons')).to eq(['payment_stage_not_reached'])
      expect(response.body).not_to include(candidate.cnic)
      expect(response.body).not_to include(candidate.mobile_number)
    end

    it 'rejects missing, invalid, revoked, or expired candidate sessions' do
      candidate = create(:candidate)

      get '/api/v1/candidate/profile'
      expect(response).to have_http_status(:unauthorized)

      get '/api/v1/candidate/profile', headers: { 'Authorization' => 'Bearer invalid.token' }
      expect(response).to have_http_status(:unauthorized)

      token = candidate_access_token_for(candidate)
      CandidateSession.last.revoke!
      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)

      token = candidate_access_token_for(candidate)
      travel_to((CandidateAuthentication::TokenIssuer::ACCESS_TOKEN_TTL + 1.second).from_now) do
        get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{token}" }
      end
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects inactive candidates and staff tokens' do
      candidate = create(:candidate, active: false)
      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin', password: 'Password123!')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
      staff_token = response.parsed_body.dig('data', 'access_token')

      get '/api/v1/candidate/profile', headers: { 'Authorization' => "Bearer #{staff_token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns Urdu error messages when requested' do
      get '/api/v1/candidate/profile',
          headers: { 'Authorization' => 'Bearer invalid.token', 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq(I18n.t('api.errors.unauthorized', locale: :ur))
      expect(response.headers['Content-Language']).to eq('ur')
    end
  end
end

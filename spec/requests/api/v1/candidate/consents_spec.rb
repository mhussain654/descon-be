# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Consent', type: :request do
  def candidate_access_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  def candidate_auth_headers(candidate, extra_headers = {})
    { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }.merge(extra_headers)
  end

  describe 'GET /api/v1/candidate/consent' do
    it 'reports acceptance false and reachable even when the candidate has not yet accepted' do
      candidate = create(:candidate, :without_consent)

      get '/api/v1/candidate/consent', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'accepted')).to be(false)
      expect(response.parsed_body.dig('data', 'accepted_at')).to be_nil
      expect(response.parsed_body.dig('data', 'current_policy_version')).to eq(CandidateConsent::CURRENT_POLICY_VERSION)
    end

    it 'reports the accepted timestamp once the candidate has accepted' do
      candidate = create(:candidate)

      get '/api/v1/candidate/consent', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'accepted')).to be(true)
      expect(response.parsed_body.dig('data', 'accepted_at')).to be_present
    end

    it 'rejects inactive candidates and staff tokens' do
      inactive_candidate = create(:candidate, active: false)

      get '/api/v1/candidate/consent', headers: candidate_auth_headers(inactive_candidate)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin', password: 'Password123!')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }

      get '/api/v1/candidate/consent',
          headers: { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/candidate/consent' do
    it 'records acceptance for a candidate who has not yet accepted' do
      candidate = create(:candidate, :without_consent)

      post '/api/v1/candidate/consent', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'accepted')).to be(true)
      expect(response.parsed_body.dig('data', 'accepted_at')).to be_present
      expect(candidate.candidate_consents.count).to eq(1)
      expect(candidate.candidate_consents.first.policy_version).to eq(CandidateConsent::CURRENT_POLICY_VERSION)
    end

    it 'unblocks subsequent candidate endpoints once accepted' do
      candidate = create(:candidate, :without_consent)
      create(:candidate_assignment, candidate:)

      post '/api/v1/candidate/consent', headers: candidate_auth_headers(candidate)
      expect(response).to have_http_status(:created)

      get '/api/v1/candidate/profile', headers: candidate_auth_headers(candidate)
      expect(response).to have_http_status(:ok)
    end

    it 'is idempotent for a candidate who already accepted the current version' do
      candidate = create(:candidate)

      expect do
        post '/api/v1/candidate/consent', headers: candidate_auth_headers(candidate)
      end.not_to change(CandidateConsent, :count)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'accepted')).to be(true)
    end

    it 'rejects inactive candidates and staff tokens' do
      inactive_candidate = create(:candidate, active: false)

      post '/api/v1/candidate/consent', headers: candidate_auth_headers(inactive_candidate)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin', password: 'Password123!')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }

      post '/api/v1/candidate/consent',
           headers: { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

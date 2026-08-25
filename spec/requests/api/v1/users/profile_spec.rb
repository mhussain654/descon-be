# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 User Profile', type: :request do
  before do
    ensure_staff_authorization_reference_data!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.fetch('data')
  end

  describe 'GET /api/v1/users/profile' do
    it 'returns the authenticated profile for every supported active staff role' do
      %w[admin hr mps finance management].each do |role|
        user = create(:user, role:, email: "#{role}-profile@example.com", password: 'Password123!')
        tokens = login_as(user)

        get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('data', 'email')).to eq(user.email)
        expect(response.parsed_body.dig('data', 'role')).to eq(role)
      end
    end

    it 'denies access when the role is inactive' do
      user = create(:user, role: 'management', email: 'inactive-role-profile@example.com', password: 'Password123!')
      tokens = login_as(user)
      user.staff_role.update!(active: false)

      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
    end

    it 'rejects requests without authentication' do
      get '/api/v1/users/profile'

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects an invalid jwt' do
      get '/api/v1/users/profile', headers: { 'Authorization' => 'Bearer invalid.token' }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects an expired staff token' do
      user = create(:user, role: 'management', email: 'management-profile@example.com', password: 'Password123!')
      tokens = login_as(user)

      travel_to((Authentication::TokenIssuer::ACCESS_TOKEN_TTL + 1.second).from_now) do
        get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }
      end

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects a candidate token on a staff endpoint' do
      candidate = create(:candidate)
      candidate_session = create(:candidate_session, candidate:)
      token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)

      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects revoked staff sessions even with an otherwise valid access token' do
      user = create(:user, role: 'management', email: 'revoked-management@example.com', password: 'Password123!')
      tokens = login_as(user)
      Session.last.revoke!

      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unauthorized')
    end

    it 'rejects inactive users even with a previously issued token' do
      user = create(:user, role: 'management', email: 'inactive-management@example.com', password: 'Password123!')
      tokens = login_as(user)
      user.update!(active: false)

      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')
    end
  end
end

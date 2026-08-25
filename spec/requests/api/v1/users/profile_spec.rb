# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 User Profile', type: :request do
  let!(:user) { create(:user, role: 'management', email: 'management-profile@example.com', password: 'Password123!') }

  def login!
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.fetch('data')
  end

  it 'returns the authenticated profile with trusted server-side role data' do
    tokens = login!

    get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'email')).to eq(user.email)
    expect(response.parsed_body.dig('data', 'role')).to eq('management')
  end

  it 'rejects requests without authentication' do
    get '/api/v1/users/profile'

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an invalid jwt' do
    get '/api/v1/users/profile', headers: { 'Authorization' => 'Bearer invalid.token' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an expired staff token' do
    tokens = login!

    travel_to((Authentication::TokenIssuer::ACCESS_TOKEN_TTL + 1.second).from_now) do
      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }
    end

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a candidate token on a staff endpoint' do
    candidate = create(:candidate)
    candidate_session = create(:candidate_session, candidate:)
    token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)

    get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects inactive users even with a previously issued token' do
    tokens = login!
    user.update!(active: false)

    get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')
  end
end

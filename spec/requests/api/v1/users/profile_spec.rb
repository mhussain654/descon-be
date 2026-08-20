# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 User Profile', type: :request do
  let!(:user) { create(:user, password: 'Password123!') }

  def login!
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.fetch('data')
  end

  it 'returns the authenticated profile' do
    tokens = login!

    get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{tokens.fetch('access_token')}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'email')).to eq(user.email)
  end

  it 'rejects an invalid jwt' do
    get '/api/v1/users/profile', headers: { 'Authorization' => 'Bearer invalid.token' }

    expect(response).to have_http_status(:unauthorized)
  end
end

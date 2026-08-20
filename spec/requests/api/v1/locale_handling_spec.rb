# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Locale Handling', type: :request do
  let!(:user) { create(:user, email: 'admin@example.com', password: 'Password123!') }

  it 'uses X-Locale when it is supported' do
    post '/api/v1/auth/login',
         params: { auth: { email: user.email, password: 'wrong-password' } },
         headers: { 'X-Locale' => 'ur' }

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['Content-Language']).to eq('ur')
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq('درست اسناد فراہم نہیں کی گئیں۔')
  end

  it 'falls back to Accept-Language when X-Locale is unsupported' do
    post '/api/v1/auth/login',
         params: { auth: { email: user.email, password: 'wrong-password' } },
         headers: {
           'X-Locale' => 'fr',
           'Accept-Language' => 'ur-PK,ur;q=0.9,en;q=0.8'
         }

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['Content-Language']).to eq('ur')
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq('درست اسناد فراہم نہیں کی گئیں۔')
  end

  it 'uses the default locale when locale headers are missing' do
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'wrong-password' } }

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['Content-Language']).to eq('en')
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Invalid credentials.')
  end

  it 'falls back to the default locale when all requested locales are unsupported' do
    post '/api/v1/auth/login',
         params: { auth: { email: user.email, password: 'wrong-password' } },
         headers: {
           'X-Locale' => 'fr',
           'Accept-Language' => 'de-DE,de;q=0.9'
         }

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['Content-Language']).to eq('en')
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Invalid credentials.')
  end

  it 'falls back to the next acceptable language when a locale has q=0' do
    post '/api/v1/auth/login',
         params: { auth: { email: user.email, password: 'wrong-password' } },
         headers: { 'Accept-Language' => 'ur;q=0,en;q=0.8' }

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['Content-Language']).to eq('en')
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Invalid credentials.')
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Auth Sessions', type: :request do
  let!(:user) { create(:user, email: 'admin@example.com', password: 'Password123!') }

  describe 'POST /api/v1/auth/login' do
    it 'returns an access token and refresh token' do
      post '/api/v1/auth/login', params: {
        auth: {
          email: user.email,
          password: 'Password123!'
        }
      }

      expect(response).to have_http_status(:created)

      body = response.parsed_body
      expect(body.dig('data', 'access_token')).to be_present
      expect(body.dig('data', 'refresh_token')).to be_present
      expect(body.dig('data', 'user', 'email')).to eq(user.email)
    end

    it 'returns a generic unauthorized error for an unknown email' do
      post '/api/v1/auth/login', params: { auth: { email: 'missing@example.com', password: 'Password123!' } }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Invalid credentials.')
    end

    it 'returns a generic unauthorized error for a bad password' do
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'wrong-password' } }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Invalid credentials.')
    end

    it 'returns bad_request when parameters are missing' do
      post '/api/v1/auth/login', params: {}

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('auth')
    end
  end

  describe 'POST /api/v1/auth/refresh' do
    let(:login_response) do
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
      response.parsed_body.fetch('data')
    end

    it 'rotates the refresh token' do
      post '/api/v1/auth/refresh', params: { auth: { refresh_token: login_response.fetch('refresh_token') } }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'refresh_token')).to be_present
      expect(response.parsed_body.dig('data', 'refresh_token')).not_to eq(login_response.fetch('refresh_token'))
    end

    it 'rejects an expired refresh token' do
      refresh_token = login_response.fetch('refresh_token')
      RefreshToken.last.update!(expires_at: 1.minute.ago)

      post '/api/v1/auth/refresh', params: { auth: { refresh_token: refresh_token } }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'revokes the session when a rotated token is reused' do
      refresh_token = login_response.fetch('refresh_token')
      access_token = login_response.fetch('access_token')

      post '/api/v1/auth/refresh', params: { auth: { refresh_token: refresh_token } }
      expect(response).to have_http_status(:ok)

      post '/api/v1/auth/refresh', params: { auth: { refresh_token: refresh_token } }
      expect(response).to have_http_status(:unauthorized)

      get '/api/v1/users/profile', headers: { 'Authorization' => "Bearer #{access_token}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/auth/logout' do
    def login!
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
      response.parsed_body.dig('data', 'access_token')
    end

    it 'revokes the current session' do
      access_token = login!

      delete '/api/v1/auth/logout', headers: { 'Authorization' => "Bearer #{access_token}" }

      expect(response).to have_http_status(:ok)
      expect(Session.last).to be_revoked
    end

    it 'replays a successful logout when the same idempotency key is retried' do
      access_token = login!
      headers = {
        'Authorization' => "Bearer #{access_token}",
        'Idempotency-Key' => 'logout-123'
      }

      delete '/api/v1/auth/logout', headers: headers
      first_response = response.parsed_body

      delete '/api/v1/auth/logout', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(response.parsed_body).to eq(first_response)
      expect(IdempotencyKey.count).to eq(1)
    end

    it 'returns a conflict when the same logout key is reused with a different request fingerprint' do
      access_token = login!
      headers = {
        'Authorization' => "Bearer #{access_token}",
        'Idempotency-Key' => 'logout-123'
      }

      delete '/api/v1/auth/logout', headers: headers
      delete '/api/v1/auth/logout?reason=manual', headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('idempotency_conflict')
    end

    it 'rejects an invalid idempotency key before processing the mutation' do
      access_token = login!

      delete '/api/v1/auth/logout',
             headers: {
               'Authorization' => "Bearer #{access_token}",
               'Idempotency-Key' => 'bad key with spaces'
             }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_idempotency_key')
      expect(Session.last).not_to be_revoked
    end
  end
end

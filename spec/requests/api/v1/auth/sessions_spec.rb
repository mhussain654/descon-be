# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Auth Sessions', type: :request do
  describe 'POST /api/v1/auth/login' do
    let!(:user) { create(:user, email: 'admin@example.com', password: 'Password123!') }

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
  end
end

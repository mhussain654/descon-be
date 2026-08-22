# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Health', type: :request do
  describe 'GET /api/v1/health/live' do
    it 'returns a live response' do
      get '/api/v1/health/live'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'status')).to eq('ok')
      expect(response.parsed_body.dig('data', 'message')).to eq('Application is live.')
      expect(response.headers['Vary']).to include('Accept-Language', 'X-Locale')
    end

    it 'keeps status machine-readable while localizing the message' do
      get '/api/v1/health/live', headers: { 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'status')).to eq('ok')
      expect(response.parsed_body.dig('data', 'message')).to eq('ایپلیکیشن فعال ہے۔')
      expect(response.headers['Content-Language']).to eq('ur')
    end
  end

  describe 'GET /api/v1/health/ready' do
    it 'returns a ready response' do
      get '/api/v1/health/ready'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'status')).to eq('ready')
      expect(response.parsed_body.dig('data', 'message')).to eq('Application is ready.')
      expect(response.headers['Vary']).to include('Accept-Language', 'X-Locale')
    end

    it 'keeps status machine-readable while localizing the readiness message' do
      get '/api/v1/health/ready', headers: { 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'status')).to eq('ready')
      expect(response.parsed_body.dig('data', 'message')).to eq('ایپلیکیشن تیار ہے۔')
      expect(response.headers['Content-Language']).to eq('ur')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Health', type: :request do
  describe 'GET /api/v1/health/live' do
    it 'returns a live response' do
      get '/api/v1/health/live'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'status')).to eq('ok')
    end
  end
end

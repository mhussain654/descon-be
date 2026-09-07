# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Management Dashboard', type: :request do
  before do
    ensure_staff_authorization_reference_data!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{login_as(user)}" }
  end

  describe 'GET /api/v1/admin/management_dashboard' do
    it 'allows a management staff member to view the dashboard summary' do
      management = create(:user, role: 'management')

      get '/api/v1/admin/management_dashboard', headers: auth_headers(management)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body['data']
      expect(data.keys).to contain_exactly(
        'conversion_funnel', 'outcome_tracking', 'mobilization', 'mobilization_trend'
      )
    end

    it 'rejects an unsupported granularity' do
      management = create(:user, role: 'management')

      get '/api/v1/admin/management_dashboard', params: { granularity: 'yearly' }, headers: auth_headers(management)

      expect(response).to have_http_status(:bad_request)
    end

    it 'forbids a staff member without view_management_dashboard (e.g. mps)' do
      mps = create(:user, role: 'mps')

      get '/api/v1/admin/management_dashboard', headers: auth_headers(mps)

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/management_dashboard'

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

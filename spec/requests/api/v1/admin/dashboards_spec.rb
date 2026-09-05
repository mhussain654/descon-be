# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Dashboard', type: :request do
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

  describe 'GET /api/v1/admin/dashboard' do
    it 'allows an admin to view the dashboard summary' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/dashboard', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body['data']
      expect(data.keys).to contain_exactly(
        'candidate_workload', 'workflow_stage_queue', 'document_review_queue', 'payment_summary'
      )
      expect(data.fetch('document_review_queue').keys).to contain_exactly(
        'pending_review', 'verified', 'rejected', 'expired_pcc', 'near_expiry_pcc'
      )
    end

    it 'forbids a staff member without view_admin_dashboard (e.g. hr)' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/dashboard', headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/dashboard'

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

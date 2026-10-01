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
        'candidate_workload', 'workflow_stage_queue', 'document_review_queue', 'payment_summary',
        'conversion_funnel', 'average_stage_duration_days', 'requires_attention', 'upcoming_activities',
        'recently_updated_candidates', 'kpi_trends'
      )
      expect(data.fetch('document_review_queue').keys).to contain_exactly(
        'pending_review', 'verified', 'rejected', 'expired_pcc', 'near_expiry_pcc'
      )
      expect(data.fetch('requires_attention').pluck('code')).to contain_exactly(
        'rejected_documents', 'failed_payment', 'overdue_qvc', 'callback_required'
      )
      expect(data.fetch('kpi_trends').keys).to contain_exactly('active_candidates', 'paid_payments', 'mobilized')
    end

    it 'scopes the dashboard to filter[country_code]/project_code/craft_code' do
      admin = create(:user, role: 'admin')
      country = create(:country)
      project = create(:project)
      craft = create(:craft)
      create(:candidate_assignment, country:, project:, craft:)
      create(:candidate_assignment)

      get '/api/v1/admin/dashboard',
          params: { filter: { country_code: country.code, project_code: project.code, craft_code: craft.code } },
          headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'candidate_workload', 'total_active_candidates')).to eq(1)
    end

    it 'returns invalid_query_parameter for an unknown filter code' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/dashboard', params: { filter: { country_code: 'not_a_real_country' } },
                                     headers: auth_headers(admin)

      expect(response).to have_http_status(:bad_request)
      error = response.parsed_body.dig('errors', 0)
      expect(error.fetch('code')).to eq('invalid_query_parameter')
      expect(error.fetch('field')).to eq('filter.country_code')
    end

    it 'returns unsupported_filter for an unrecognized filter name' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/dashboard', params: { filter: { status: 'verified' } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unsupported_filter')
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

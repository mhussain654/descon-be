# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 MPS Dashboard', type: :request do
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

  describe 'GET /api/v1/admin/mps_dashboard' do
    it 'allows an mps staff member to view the dashboard summary' do
      mps = create(:user, role: 'mps')

      get '/api/v1/admin/mps_dashboard', headers: auth_headers(mps)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body['data']
      expect(data.keys).to contain_exactly(
        'workflow_stage_queue', 'delayed_cases', 'craft_summary', 'mobilization', 'mobilization_trend',
        'conversion_funnel', 'latest_mobilization', 'attention_candidates'
      )
      expect(data.fetch('conversion_funnel').pluck('code')).to contain_exactly('documents_uploaded', 'verified',
                                                                               'mobilized')
      expect(data.fetch('latest_mobilization')).to be_nil
    end

    it 'returns scoped delayed candidates with backend stage age and priority' do
      mps = create(:user, role: 'mps')
      country = create(:country)
      assignment = create(:candidate_assignment, country:, created_at: 20.days.ago)
      create(:candidate_assignment, created_at: 30.days.ago)

      get '/api/v1/admin/mps_dashboard', params: { filter: { country_code: country.code } }, headers: auth_headers(mps)

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body.dig('data', 'attention_candidates')
      expect(rows.size).to eq(1)
      expect(rows.first).to include('candidate_public_id' => assignment.candidate.public_id,
                                   'days_waiting' => 20, 'severity' => 'critical')
    end

    it 'accepts a granularity param for the trend section' do
      mps = create(:user, role: 'mps')

      get '/api/v1/admin/mps_dashboard', params: { granularity: 'daily' }, headers: auth_headers(mps)

      expect(response).to have_http_status(:ok)
    end

    it 'rejects an unsupported granularity' do
      mps = create(:user, role: 'mps')

      get '/api/v1/admin/mps_dashboard', params: { granularity: 'yearly' }, headers: auth_headers(mps)

      expect(response).to have_http_status(:bad_request)
    end

    it 'scopes the dashboard to filter[country_code]/project_code/craft_code' do
      mps = create(:user, role: 'mps')
      country = create(:country)
      create(:candidate_assignment, country:)
      create(:candidate_assignment)

      get '/api/v1/admin/mps_dashboard', params: { filter: { country_code: country.code } }, headers: auth_headers(mps)

      expect(response).to have_http_status(:ok)
      workflow_stage_queue = response.parsed_body.dig('data', 'workflow_stage_queue')
      expect(workflow_stage_queue.sum { |row| row['count'] }).to eq(1)
    end

    it 'returns invalid_query_parameter for an unknown filter code' do
      mps = create(:user, role: 'mps')

      get '/api/v1/admin/mps_dashboard', params: { filter: { country_code: 'not_a_real_country' } },
                                         headers: auth_headers(mps)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_query_parameter')
    end

    it 'forbids a staff member without view_mps_dashboard (e.g. hr)' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/mps_dashboard', headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/mps_dashboard'

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

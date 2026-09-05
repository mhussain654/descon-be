# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe 'API V1 Admin Reports', type: :request do
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

  describe 'GET /api/v1/admin/reports' do
    it 'lists the available report types for a permitted staff member' do
      management = create(:user, role: 'management')

      get '/api/v1/admin/reports', headers: auth_headers(management)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to contain_exactly(
        'status_summary', 'mobilization', 'craft_summary', 'outcome_tracking', 'conversion', 'trend'
      )
    end

    it 'forbids a staff member without view_reports (e.g. hr)' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/reports', headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/reports'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/admin/reports/:report_type' do
    it 'returns the requested report data' do
      mps = create(:user, role: 'mps')

      get '/api/v1/admin/reports/status_summary', headers: auth_headers(mps)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to be_an(Array)
    end

    it 'rejects an unknown report type' do
      mps = create(:user, role: 'mps')

      get '/api/v1/admin/reports/bogus', headers: auth_headers(mps)

      expect(response).to have_http_status(:bad_request)
    end

    it 'forbids a staff member without view_reports' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/reports/status_summary', headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/admin/reports/:report_type/export' do
    it 'exports a report as CSV' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/reports/status_summary/export', params: { format: 'csv' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/csv')
      expect(response.headers['Content-Disposition']).to include('status_summary.csv')
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      parsed = CSV.parse(response.body, headers: true)
      expect(parsed.headers).to eq(%w[code position count])
    end

    it 'exports a report as XLSX' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/reports/craft_summary/export', params: { format: 'xlsx' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      expect(response.body[0..1]).to eq('PK')
    end

    it 'exports a report as PDF' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/reports/conversion/export', params: { format: 'pdf' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/pdf')
      expect(response.body[0..4]).to eq('%PDF-')
    end

    it 'rejects an unsupported export format' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/reports/status_summary/export', params: { format: 'doc' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:bad_request)
    end

    it 'forbids a staff member without view_reports' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/reports/status_summary/export', params: { format: 'csv' }, headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
    end
  end
end

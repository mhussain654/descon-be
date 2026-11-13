# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Flight Detail Setting', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    FlightDetailSetting.delete_all
  end

  def auth_headers(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}",
      'Content-Type' => 'application/json' }
  end

  let(:defaults) do
    { airline: 'Qatar Airways', flight_number: 'QR-615', sector: 'LHE-DOH', departure_on: '2026-11-20',
      departure_time: '14:30' }
  end

  describe 'GET /api/v1/admin/flight_detail_setting' do
    it 'returns the blank defaults to staff who move candidates (MPS)' do
      get '/api/v1/admin/flight_detail_setting', headers: auth_headers(create(:user, role: 'mps'))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data')).to include('airline' => nil, 'departure_on' => nil,
                                                            'departure_time' => nil)
    end

    it 'is forbidden to staff who only view the workflow (HR)' do
      get '/api/v1/admin/flight_detail_setting', headers: auth_headers(create(:user, role: 'hr'))

      expect(response).to have_http_status(:forbidden)
    end

    it 'requires a staff login' do
      get '/api/v1/admin/flight_detail_setting'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/flight_detail_setting' do
    it 'saves the defaults, records who changed them and audits the change' do
      admin = create(:user, role: 'admin')

      patch '/api/v1/admin/flight_detail_setting', params: { flight_detail_setting: defaults }.to_json,
                                                   headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data')).to include(defaults.stringify_keys)
      expect(FlightDetailSetting.current.updated_by).to eq(admin)
      expect(AuditEvent.where(action_code: 'flight_detail_setting_updated')).to exist
    end

    it 'refuses a departure date without a time' do
      patch '/api/v1/admin/flight_detail_setting',
            params: { flight_detail_setting: { departure_on: '2026-11-20' } }.to_json,
            headers: auth_headers(create(:user, role: 'admin'))

      expect(response).to have_http_status(:unprocessable_content)
      expect(FlightDetailSetting.current.departure_on).to be_nil
    end

    it 'does not let HR change the defaults' do
      patch '/api/v1/admin/flight_detail_setting', params: { flight_detail_setting: defaults }.to_json,
                                                   headers: auth_headers(create(:user, role: 'hr'))

      expect(response).to have_http_status(:forbidden)
      expect(FlightDetailSetting.current.airline).to be_nil
    end
  end
end

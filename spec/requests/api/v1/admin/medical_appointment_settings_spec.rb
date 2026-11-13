# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Medical Appointment Setting', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    MedicalAppointmentSetting.delete_all
  end

  def auth_headers(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}",
      'Content-Type' => 'application/json' }
  end

  let(:defaults) do
    { center_name: 'Al Shifa Medical Centre', center_address: '12 Mall Road, Lahore', appointment_on: '2026-11-20',
      appointment_time: '09:30' }
  end

  describe 'GET /api/v1/admin/medical_appointment_setting' do
    it 'returns the blank defaults to staff who move candidates (MPS)' do
      get '/api/v1/admin/medical_appointment_setting', headers: auth_headers(create(:user, role: 'mps'))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data')).to include('center_name' => nil, 'appointment_on' => nil,
                                                            'appointment_time' => nil)
    end

    it 'is forbidden to staff who only view the workflow (HR)' do
      get '/api/v1/admin/medical_appointment_setting', headers: auth_headers(create(:user, role: 'hr'))

      expect(response).to have_http_status(:forbidden)
    end

    it 'requires a staff login' do
      get '/api/v1/admin/medical_appointment_setting'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/medical_appointment_setting' do
    it 'saves the defaults, records who changed them and audits the change' do
      admin = create(:user, role: 'admin')

      patch '/api/v1/admin/medical_appointment_setting', params: { medical_appointment_setting: defaults }.to_json,
                                                         headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data')).to include(defaults.stringify_keys)
      expect(MedicalAppointmentSetting.current.updated_by).to eq(admin)
      expect(AuditEvent.where(action_code: 'medical_appointment_setting_updated')).to exist
    end

    it 'refuses a time that is not HH:MM' do
      patch '/api/v1/admin/medical_appointment_setting',
            params: { medical_appointment_setting: { appointment_time: '9.30' } }.to_json,
            headers: auth_headers(create(:user, role: 'admin'))

      expect(response).to have_http_status(:unprocessable_content)
      expect(MedicalAppointmentSetting.current.appointment_time).to be_nil
    end

    it 'does not let HR change the defaults' do
      patch '/api/v1/admin/medical_appointment_setting', params: { medical_appointment_setting: defaults }.to_json,
                                                         headers: auth_headers(create(:user, role: 'hr'))

      expect(response).to have_http_status(:forbidden)
      expect(MedicalAppointmentSetting.current.center_name).to be_nil
    end
  end
end

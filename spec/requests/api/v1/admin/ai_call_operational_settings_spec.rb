# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin AI Call Operational Settings', type: :request do
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

  describe 'GET /api/v1/admin/ai_call_operational_settings' do
    it 'returns the singleton row (creating it lazily) for an authorized admin' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/ai_call_operational_settings', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'outbound_trigger_cooldown_minutes')).to be_nil
      expect(AiCallOperationalSetting.count).to eq(1)
    end

    it 'forbids a staff member without manage_ai_call_settings' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/ai_call_operational_settings', headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/ai_call_operational_settings'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/ai_call_operational_settings' do
    it 'updates the knobs, recording the actor and an audit event with before/after values' do
      admin = create(:user, role: 'admin')
      AiCallOperationalSetting.current.update!(daily_outbound_call_limit: 100)

      patch '/api/v1/admin/ai_call_operational_settings',
            params: { ai_call_operational_setting: { daily_outbound_call_limit: 50, calling_hours_start: 8 } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'daily_outbound_call_limit')).to eq(50)
      expect(response.parsed_body.dig('data', 'calling_hours_start')).to eq(8)
      expect(response.parsed_body.dig('data', 'updated_by', 'id')).to eq(admin.public_id)

      audit = AuditEvent.find_by(entity_type: 'AiCallOperationalSetting',
                                 action_code: 'ai_call_operational_setting_updated')
      expect(audit.actor).to eq(admin)
      expect(audit.metadata.dig('changes', 'daily_outbound_call_limit')).to eq([100, 50])
      expect(audit.metadata.dig('changes', 'calling_hours_start')).to eq([nil, 8])
    end

    it 'does not record an audit event when nothing actually changes' do
      admin = create(:user, role: 'admin')
      AiCallOperationalSetting.current.update!(daily_outbound_call_limit: 50)

      expect do
        patch '/api/v1/admin/ai_call_operational_settings',
              params: { ai_call_operational_setting: { daily_outbound_call_limit: 50 } }.to_json,
              headers: auth_headers(admin).merge('Content-Type' => 'application/json')
      end.not_to change(AuditEvent, :count)

      expect(response).to have_http_status(:ok)
    end

    it 'forbids a staff member without manage_ai_call_settings' do
      hr = create(:user, role: 'hr')

      patch '/api/v1/admin/ai_call_operational_settings',
            params: { ai_call_operational_setting: { daily_outbound_call_limit: 50 } }.to_json,
            headers: auth_headers(hr).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an invalid update (calling_hours_start out of range)' do
      admin = create(:user, role: 'admin')

      patch '/api/v1/admin/ai_call_operational_settings',
            params: { ai_call_operational_setting: { calling_hours_start: 24 } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'immediately changes AiCalls::Configuration behavior for subsequent reads' do
      admin = create(:user, role: 'admin')

      patch '/api/v1/admin/ai_call_operational_settings',
            params: { ai_call_operational_setting: { daily_outbound_call_limit: 7 } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(AiCalls::Configuration.new.daily_outbound_call_limit).to eq(7)
    end
  end
end

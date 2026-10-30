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
    it 'returns the singleton row (creating it lazily) for the developer' do
      developer = create(:user, role: 'developer')

      get '/api/v1/admin/ai_call_operational_settings', headers: auth_headers(developer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'outbound_trigger_cooldown_minutes')).to be_nil
      expect(AiCallOperationalSetting.count).to eq(1)
    end

    it 'returns the default each knob uses while it is blank' do
      developer = create(:user, role: 'developer')

      get '/api/v1/admin/ai_call_operational_settings', headers: auth_headers(developer)

      expect(response.parsed_body.dig('data', 'defaults')).to eq(
        'outbound_trigger_cooldown_minutes' => 15, 'daily_outbound_call_limit' => 1000,
        'admin_trigger_rate_limit_per_hour' => 50, 'calling_hours_start' => 9,
        'calling_hours_end' => 19, 'max_call_duration_minutes' => 15
      )
    end

    it 'forbids admin and other staff: the call limits are developer-only' do
      %w[admin hr].each do |role|
        get '/api/v1/admin/ai_call_operational_settings', headers: auth_headers(create(:user, role:))

        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/ai_call_operational_settings'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/ai_call_operational_settings' do
    it 'updates the knobs, recording the actor and an audit event with before/after values' do
      admin = create(:user, role: 'developer')
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
      admin = create(:user, role: 'developer')
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
      admin = create(:user, role: 'developer')

      patch '/api/v1/admin/ai_call_operational_settings',
            params: { ai_call_operational_setting: { calling_hours_start: 24 } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'immediately changes AiCalls::Configuration behavior for subsequent reads' do
      admin = create(:user, role: 'developer')

      patch '/api/v1/admin/ai_call_operational_settings',
            params: { ai_call_operational_setting: { daily_outbound_call_limit: 7 } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(AiCalls::Configuration.new.daily_outbound_call_limit).to eq(7)
    end

    it 'sets the human transfer destination number, reflected immediately in AiCalls::Configuration' do
      admin = create(:user, role: 'developer')

      patch '/api/v1/admin/ai_call_operational_settings',
            params: { ai_call_operational_setting: { human_transfer_phone_number: '+923001234567' } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'human_transfer_phone_number')).to eq('+923001234567')
      expect(AiCalls::Configuration.new.human_transfer_phone_number).to eq('+923001234567')
    end

    it 'rejects a malformed human transfer phone number' do
      admin = create(:user, role: 'developer')

      patch '/api/v1/admin/ai_call_operational_settings',
            params: { ai_call_operational_setting: { human_transfer_phone_number: 'not-a-number' } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end

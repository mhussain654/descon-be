# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 SMS Templates', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    SmsTemplate::MESSAGE_CODES.reverse_each { |code| create(:sms_template, message_code: code, template_id_en: nil) }
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{login_as(user)}" }
  end

  def json_headers(user)
    auth_headers(user).merge('Content-Type' => 'application/json')
  end

  describe 'GET /api/v1/admin/sms_templates' do
    it 'lists every message in the order a candidate gets them, with the values each template must use' do
      get '/api/v1/admin/sms_templates', headers: auth_headers(create(:user, role: 'developer'))

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      expect(data.pluck('message_code')).to eq(SmsTemplate::MESSAGE_CODES)
      expect(data.first).to include('message_code' => 'otp', 'enabled' => true, 'can_disable' => false,
                                    'variables' => %w[code minutes], 'template_id_en' => nil, 'updated_by' => nil)
      expect(data.find { |row| row['message_code'] == 'fee_pending' })
        .to include('can_disable' => true, 'variables' => %w[name amount])
    end

    it 'forbids an admin: SMS settings are developer-only' do
      get '/api/v1/admin/sms_templates', headers: auth_headers(create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/sms_templates'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/sms_templates/:message_code' do
    it 'saves the template ids and switch, recording the actor and an audit event of what changed' do
      developer = create(:user, role: 'developer')

      patch '/api/v1/admin/sms_templates/fee_pending',
            params: { sms_template: { template_id_en: '20010', template_id_ur: '20011', enabled: false } }.to_json,
            headers: json_headers(developer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data'))
        .to include('template_id_en' => '20010', 'template_id_ur' => '20011', 'enabled' => false,
                    'updated_by' => { 'id' => developer.public_id, 'role' => 'developer' })
      expect(SmsTemplate.find_for(:fee_pending)).to have_attributes(template_id_en: '20010', updated_by: developer)
      audit = AuditEvent.find_by!(action_code: 'sms_template_updated')
      expect(audit.metadata).to include('message_code' => 'fee_pending')
      expect(audit.metadata['changes'].keys).to match_array(%w[template_id_en template_id_ur enabled])
    end

    it 'clears a template id with a blank value and records no audit event when nothing changed' do
      SmsTemplate.find_for(:registered).update!(template_id_en: '20001')
      headers = json_headers(create(:user, role: 'developer'))

      params = { sms_template: { template_id_en: '' } }.to_json
      2.times { patch '/api/v1/admin/sms_templates/registered', params:, headers: }

      expect(SmsTemplate.find_for(:registered).template_id_en).to be_nil
      expect(AuditEvent.where(action_code: 'sms_template_updated').count).to eq(1)
    end

    it 'refuses to switch off the OTP' do
      patch '/api/v1/admin/sms_templates/otp', params: { sms_template: { enabled: false } }.to_json,
                                               headers: json_headers(create(:user, role: 'developer'))

      expect(response).to have_http_status(:unprocessable_content)
      expect(SmsTemplate.find_for(:otp).enabled).to be(true)
    end

    it 'rejects a template id that is not a number' do
      patch '/api/v1/admin/sms_templates/registered', params: { sms_template: { template_id_en: 'abc' } }.to_json,
                                                      headers: json_headers(create(:user, role: 'developer'))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns not found for an unknown message' do
      patch '/api/v1/admin/sms_templates/birthday', params: { sms_template: { enabled: false } }.to_json,
                                                    headers: json_headers(create(:user, role: 'developer'))

      expect(response).to have_http_status(:not_found)
    end

    it 'forbids an admin' do
      patch '/api/v1/admin/sms_templates/registered', params: { sms_template: { enabled: false } }.to_json,
                                                      headers: json_headers(create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
      expect(SmsTemplate.find_for(:registered).enabled).to be(true)
    end
  end
end

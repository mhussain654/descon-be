# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 App Feature Setting', type: :request do
  before { ensure_staff_authorization_reference_data! }

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

  describe 'GET /api/v1/admin/app_feature_setting' do
    it 'returns every switch, each SMS message and whether the server is set up for it' do
      get '/api/v1/admin/app_feature_setting', headers: auth_headers(create(:user, role: 'developer'))

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      expect(data).to include('card_payment_enabled' => true, 'voucher_payment_enabled' => true,
                              'progress_sms_enabled' => true, 'automatic_calls_enabled' => true,
                              'bulk_calls_enabled' => true, 'document_ocr_enabled' => true)
      expect(data['sms_messages'].pluck('code')).to eq(CandidateSmsDelivery::MESSAGE_CODES)
      expect(data['sms_messages'].first).to include('enabled' => true, 'template_ready' => false)
      expect(data['server_ready'].keys).to match_array(%w[card_payment voucher_payment progress_sms automatic_calls
                                                          bulk_calls document_ocr])
    end

    it 'forbids an admin: the feature switches are developer-only' do
      get '/api/v1/admin/app_feature_setting', headers: auth_headers(create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/app_feature_setting'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/app_feature_setting' do
    it 'saves the switches, recording the actor and an audit event of what changed' do
      developer = create(:user, role: 'developer')

      patch '/api/v1/admin/app_feature_setting',
            params: { app_feature_setting: { voucher_payment_enabled: false,
                                             disabled_sms_messages: %w[fee_pending] } }.to_json,
            headers: json_headers(developer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'voucher_payment_enabled')).to be(false)
      expect(response.parsed_body.dig('data', 'sms_messages').find { |m| m['code'] == 'fee_pending' })
        .to include('enabled' => false)
      expect(AppFeatureSetting.current).to have_attributes(voucher_payment_enabled: false, updated_by: developer)
      audit = AuditEvent.find_by!(action_code: 'app_feature_setting_updated')
      expect(audit.metadata['changes'].keys).to match_array(%w[voucher_payment_enabled disabled_sms_messages])
    end

    it 'turns every SMS message back on with an empty list' do
      AppFeatureSetting.current.update!(disabled_sms_messages: %w[fee_pending])

      patch '/api/v1/admin/app_feature_setting',
            params: { app_feature_setting: { disabled_sms_messages: [] } }.to_json,
            headers: json_headers(create(:user, role: 'developer'))

      expect(AppFeatureSetting.current.disabled_sms_messages).to eq([])
    end

    it 'rejects an unknown SMS message' do
      patch '/api/v1/admin/app_feature_setting',
            params: { app_feature_setting: { disabled_sms_messages: %w[birthday] } }.to_json,
            headers: json_headers(create(:user, role: 'developer'))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'forbids a staff member without manage_app_settings' do
      patch '/api/v1/admin/app_feature_setting',
            params: { app_feature_setting: { card_payment_enabled: false } }.to_json,
            headers: json_headers(create(:user, role: 'hr'))

      expect(response).to have_http_status(:forbidden)
      expect(AppFeatureSetting.current.card_payment_enabled).to be(true)
    end
  end
end

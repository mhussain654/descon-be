# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Support Setting', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    SupportSetting.delete_all
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

  def candidate_headers(candidate)
    candidate_session = create(:candidate_session, candidate:)
    token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/admin/support_setting' do
    it 'returns the (lazily created, still blank) singleton for an authorized admin' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/support_setting', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data')).to include('phone_number' => nil)
      expect(SupportSetting.count).to eq(1)
    end

    it 'forbids a staff member without manage_support_settings' do
      get '/api/v1/admin/support_setting', headers: auth_headers(create(:user, role: 'hr'))

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/support_setting'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/support_setting' do
    it 'saves the normalized number, recording the actor and an audit event' do
      admin = create(:user, role: 'admin')

      patch '/api/v1/admin/support_setting',
            params: { support_setting: { phone_number: '+92 300 1234567' } }.to_json, headers: json_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'phone_number')).to eq('+923001234567')
      expect(response.parsed_body.dig('data', 'updated_by', 'id')).to eq(admin.public_id)
      audit = AuditEvent.find_by(entity_type: 'SupportSetting', action_code: 'support_setting_updated')
      expect(audit.actor).to eq(admin)
      expect(audit.metadata.dig('changes', 'phone_number')).to eq([nil, '+923001234567'])
    end

    it 'does not record an audit event when nothing changes' do
      admin = create(:user, role: 'admin')
      SupportSetting.current.update!(phone_number: '+923001234567')

      expect do
        patch '/api/v1/admin/support_setting',
              params: { support_setting: { phone_number: '+923001234567' } }.to_json, headers: json_headers(admin)
      end.not_to change(AuditEvent, :count)
    end

    it 'rejects a value that is not a phone number' do
      patch '/api/v1/admin/support_setting',
            params: { support_setting: { phone_number: 'call us' } }.to_json,
            headers: json_headers(create(:user, role: 'admin'))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'forbids a staff member without manage_support_settings' do
      patch '/api/v1/admin/support_setting',
            params: { support_setting: { phone_number: '+923001234567' } }.to_json,
            headers: json_headers(create(:user, role: 'mps'))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/candidate/support_setting' do
    it 'returns only the number, once staff have set it, to any authenticated candidate' do
      SupportSetting.current.update!(phone_number: '+923001234567')

      get '/api/v1/candidate/support_setting', headers: candidate_headers(create(:candidate))

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.parsed_body.fetch('data')).to eq('phone_number' => '+923001234567')
    end

    it 'returns a null number while none is configured' do
      get '/api/v1/candidate/support_setting', headers: candidate_headers(create(:candidate))

      expect(response.parsed_body.dig('data', 'phone_number')).to be_nil
    end

    it 'denies an inactive candidate' do
      get '/api/v1/candidate/support_setting', headers: candidate_headers(create(:candidate, active: false))

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/candidate/support_setting'

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

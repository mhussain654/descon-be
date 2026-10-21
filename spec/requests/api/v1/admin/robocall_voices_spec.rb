# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Robocall Voices', type: :request do
  # db:seed (run when CI prepares the test database) installs the starter call types for real.
  before do
    RobocallVoice.delete_all
    ensure_staff_authorization_reference_data!
  end

  def auth_headers(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}",
      'Content-Type' => 'application/json' }
  end

  let(:admin) { create(:user, role: 'admin') }
  let(:finance) { create(:user, role: 'finance') }

  describe 'GET /api/v1/admin/robocall_voices' do
    it 'lists the call types by name for a permitted staff member' do
      create(:robocall_voice, name_en: 'Visa approved', name_ur: 'ویزا منظور', voice_id: '205')
      create(:robocall_voice, name_en: 'Flight', voice_id: '300', active: false)

      get '/api/v1/admin/robocall_voices', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].pluck('name_en')).to eq(['Flight', 'Visa approved'])
      expect(response.parsed_body['data'].last).to include('voice_id' => '205', 'active' => true,
                                                           'name_ur' => 'ویزا منظور')
    end

    it 'forbids staff without call permissions and rejects an anonymous request' do
      get '/api/v1/admin/robocall_voices', headers: auth_headers(finance)
      expect(response).to have_http_status(:forbidden)

      get '/api/v1/admin/robocall_voices'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/admin/robocall_voices' do
    def create_voice(user, attributes)
      post '/api/v1/admin/robocall_voices', params: { robocall_voice: attributes }.to_json, headers: auth_headers(user)
    end

    it 'adds a call type, recording the actor and an audit event' do
      create_voice(admin, { name_en: 'Flight', name_ur: 'پرواز', voice_id: '300' })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['data']).to include('name_en' => 'Flight', 'voice_id' => '300', 'active' => true)
      voice = RobocallVoice.find_by!(voice_id: '300')
      expect(voice).to have_attributes(created_by: admin, updated_by: admin)
      expect(AuditEvent.where(entity_type: 'RobocallVoice', entity_id: voice.id,
                              action_code: 'robocall_voice_created')).to exist
    end

    it 'rejects a duplicate voice id and a malformed one' do
      create(:robocall_voice, voice_id: '300')

      create_voice(admin, { name_en: 'Other', voice_id: '300' })
      expect(response).to have_http_status(:unprocessable_content)

      create_voice(admin, { name_en: 'Another', voice_id: 'bad id!' })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'forbids staff without call permissions' do
      create_voice(finance, { name_en: 'Flight', voice_id: '300' })

      expect(response).to have_http_status(:forbidden)
      expect(RobocallVoice.count).to eq(0)
    end
  end

  describe 'PATCH /api/v1/admin/robocall_voices/:id' do
    it 'renames or switches off a call type, with an audit event' do
      voice = create(:robocall_voice, name_en: 'Flight', voice_id: '300')

      patch "/api/v1/admin/robocall_voices/#{voice.public_id}",
            params: { robocall_voice: { name_en: 'Flight info', active: false } }.to_json, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(voice.reload).to have_attributes(name_en: 'Flight info', active: false, updated_by: admin)
      expect(AuditEvent.where(entity_id: voice.id, action_code: 'robocall_voice_updated')).to exist
    end

    it 'returns 404 for an unknown call type and forbids staff without call permissions' do
      patch "/api/v1/admin/robocall_voices/#{SecureRandom.uuid}",
            params: { robocall_voice: { active: false } }.to_json, headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)

      voice = create(:robocall_voice)
      patch "/api/v1/admin/robocall_voices/#{voice.public_id}",
            params: { robocall_voice: { active: false } }.to_json, headers: auth_headers(finance)
      expect(response).to have_http_status(:forbidden)
      expect(voice.reload.active).to be(true)
    end
  end
end

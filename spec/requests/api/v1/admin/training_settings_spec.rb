# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Training Setting', type: :request do
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

  def candidate_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  describe 'GET /api/v1/admin/training_setting' do
    it 'returns the singleton row (creating it lazily, seeded with the default URL) for an authorized admin' do
      admin = create(:user, role: 'admin')

      get '/api/v1/admin/training_setting', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'url')).to eq(TrainingSetting::DEFAULT_URL)
      expect(TrainingSetting.count).to eq(1)
    end

    it 'forbids a staff member without manage_training_settings' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/training_setting', headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/training_setting'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/training_setting' do
    it 'updates the link, recording the actor and an audit event with the before/after value' do
      admin = create(:user, role: 'admin')
      TrainingSetting.current

      patch '/api/v1/admin/training_setting',
            params: { training_setting: { url: 'https://www.youtube.com/@DesconManpowerTraining' } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'url')).to eq('https://www.youtube.com/@DesconManpowerTraining')
      expect(response.parsed_body.dig('data', 'updated_by', 'id')).to eq(admin.public_id)

      audit = AuditEvent.find_by(entity_type: 'TrainingSetting', action_code: 'training_setting_updated')
      expect(audit.actor).to eq(admin)
      expect(audit.metadata.dig('changes', 'url')).to eq([TrainingSetting::DEFAULT_URL, 'https://www.youtube.com/@DesconManpowerTraining'])
    end

    it 'does not record an audit event when nothing actually changes' do
      admin = create(:user, role: 'admin')
      TrainingSetting.current.update!(url: 'https://example.test/unchanged')

      expect do
        patch '/api/v1/admin/training_setting',
              params: { training_setting: { url: 'https://example.test/unchanged' } }.to_json,
              headers: auth_headers(admin).merge('Content-Type' => 'application/json')
      end.not_to change(AuditEvent, :count)

      expect(response).to have_http_status(:ok)
    end

    it 'forbids a staff member without manage_training_settings' do
      hr = create(:user, role: 'hr')

      patch '/api/v1/admin/training_setting',
            params: { training_setting: { url: 'https://example.test' } }.to_json,
            headers: auth_headers(hr).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an invalid URL' do
      admin = create(:user, role: 'admin')

      patch '/api/v1/admin/training_setting',
            params: { training_setting: { url: 'not a url' } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'immediately changes what the candidate endpoint returns' do
      admin = create(:user, role: 'admin')
      candidate = create(:candidate)

      patch '/api/v1/admin/training_setting',
            params: { training_setting: { url: 'https://example.test/updated' } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      get '/api/v1/candidate/training_setting',
          headers: { 'Authorization' => "Bearer #{candidate_token_for(candidate)}" }

      expect(response.parsed_body.dig('data', 'url')).to eq('https://example.test/updated')
    end
  end

  describe 'GET /api/v1/candidate/training_setting' do
    it "returns the current link for any authenticated candidate -- not scoped to a particular candidate's own data" do
      candidate = create(:candidate)

      get '/api/v1/candidate/training_setting',
          headers: { 'Authorization' => "Bearer #{candidate_token_for(candidate)}" }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.parsed_body.dig('data', 'url')).to eq(TrainingSetting::DEFAULT_URL)
      expect(response.parsed_body.fetch('data').keys).not_to include('updated_by')
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/candidate/training_setting'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'denies an inactive candidate' do
      candidate = create(:candidate, active: false)

      get '/api/v1/candidate/training_setting',
          headers: { 'Authorization' => "Bearer #{candidate_token_for(candidate)}" }

      expect(response).to have_http_status(:forbidden)
    end

    it 'denies a staff access token' do
      admin = create(:user, role: 'admin')

      get '/api/v1/candidate/training_setting', headers: auth_headers(admin)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

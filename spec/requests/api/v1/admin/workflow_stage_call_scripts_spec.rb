# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Workflow Stage Call Scripts', type: :request do
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

  describe 'GET /api/v1/admin/workflow_stage_call_scripts' do
    it 'lists scripts ordered by workflow_stage_code for an authorized admin' do
      admin = create(:user, role: 'admin')
      create(:workflow_stage_call_script, workflow_stage_code: 'verified')
      create(:workflow_stage_call_script, workflow_stage_code: 'fee_paid')

      get '/api/v1/admin/workflow_stage_call_scripts', headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      codes = response.parsed_body['data'].pluck('workflow_stage_code')
      expect(codes).to eq(%w[fee_paid verified])
    end

    it 'forbids a staff member without manage_ai_call_scripts' do
      finance = create(:user, role: 'finance')

      get '/api/v1/admin/workflow_stage_call_scripts', headers: auth_headers(finance)

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/workflow_stage_call_scripts'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/workflow_stage_call_scripts/:workflow_stage_code' do
    it 'updates the announcement and active flag, recording the actor and an audit event' do
      admin = create(:user, role: 'admin')
      create(:workflow_stage_call_script, workflow_stage_code: 'verified', active: false)

      patch '/api/v1/admin/workflow_stage_call_scripts/verified',
            params: { workflow_stage_call_script: { announcement: 'Approved wording.', active: true } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'announcement')).to eq('Approved wording.')
      expect(response.parsed_body.dig('data', 'active')).to be(true)
      expect(response.parsed_body.dig('data', 'updated_by', 'id')).to eq(admin.public_id)

      audit = AuditEvent.find_by(entity_type: 'WorkflowStageCallScript',
                                 action_code: 'workflow_stage_call_script_updated')
      expect(audit.actor).to eq(admin)
      expect(audit.metadata['workflow_stage_code']).to eq('verified')
    end

    it 'returns 404 for a stage with no script row' do
      admin = create(:user, role: 'admin')

      patch '/api/v1/admin/workflow_stage_call_scripts/mobilized',
            params: { workflow_stage_call_script: { active: true } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:not_found)
    end

    it 'forbids a staff member without manage_ai_call_scripts' do
      finance = create(:user, role: 'finance')
      create(:workflow_stage_call_script, workflow_stage_code: 'verified')

      patch '/api/v1/admin/workflow_stage_call_scripts/verified',
            params: { workflow_stage_call_script: { active: true } }.to_json,
            headers: auth_headers(finance).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an invalid update (blank announcement)' do
      admin = create(:user, role: 'admin')
      create(:workflow_stage_call_script, workflow_stage_code: 'verified')

      patch '/api/v1/admin/workflow_stage_call_scripts/verified',
            params: { workflow_stage_call_script: { announcement: '' } }.to_json,
            headers: auth_headers(admin).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Workflow', type: :request do
  def candidate_access_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  before do
    ensure_canonical_workflow_stages!
  end

  describe 'GET /api/v1/candidate/workflow_state' do
    it 'returns only the authenticated candidate workflow state with localized stage names and freshness headers' do
      candidate = create(:candidate, preferred_locale: 'ur')
      assignment = create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: WorkflowStage.find_by!(code: 'documents_pending')
      )
      create(
        :candidate_stage_history,
        candidate_assignment: assignment,
        from_workflow_stage: WorkflowStage.find_by!(code: 'registered'),
        to_workflow_stage: WorkflowStage.find_by!(code: 'documents_pending'),
        occurred_at: Time.zone.parse('2026-08-29T09:00:00Z')
      )
      other_candidate = create(:candidate)
      create(
        :candidate_assignment,
        candidate: other_candidate,
        current_workflow_stage: WorkflowStage.find_by!(code: 'mobilized')
      )

      get '/api/v1/candidate/workflow_state',
          params: { candidate_id: other_candidate.public_id },
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}", 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.headers['ETag']).to be_present
      expect(response.headers['Content-Language']).to eq('ur')
      expect(response.parsed_body.dig('data', 'candidate_id')).to eq(candidate.public_id)
      expect(response.parsed_body.dig('data', 'current_stage', 'code')).to eq('documents_pending')
      expect(response.parsed_body.dig('data', 'timeline', 1, 'name')).to eq(
        WorkflowStage.find_by!(code: 'documents_pending').name_for(locale: :ur)
      )
      expect(response.parsed_body.dig('data', 'timeline', 3, 'code')).to eq('under_verification')
      expect(response.parsed_body.dig('data', 'total_count')).to eq(15)
    end

    it 'rejects inactive candidates and staff tokens' do
      candidate = create(:candidate, active: false)

      get '/api/v1/candidate/workflow_state',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }

      get '/api/v1/candidate/workflow_state',
          headers: { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/candidate/workflow_history' do
    it 'returns candidate-safe workflow history without actor identity leakage' do
      candidate = create(:candidate)
      assignment = create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: WorkflowStage.find_by!(code: 'documents_uploaded')
      )
      actor = create(:user, role: 'mps')
      create(
        :candidate_stage_history,
        candidate_assignment: assignment,
        from_workflow_stage: WorkflowStage.find_by!(code: 'documents_pending'),
        to_workflow_stage: WorkflowStage.find_by!(code: 'documents_uploaded'),
        actor:,
        occurred_at: Time.zone.parse('2026-08-29T10:00:00Z'),
        metadata: { 'source' => 'manual_review_ready' }
      )

      get '/api/v1/candidate/workflow_history',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.parsed_body.dig('data', 'history', 0, 'to_stage', 'code')).to eq('documents_uploaded')
      expect(response.body).not_to include(actor.public_id)
      expect(response.body).not_to include(actor.email)
    end
  end
end

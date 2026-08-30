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
        current_workflow_stage: WorkflowStage.find_by!(code: 'documents_pending'),
        created_at: Time.zone.parse('2026-08-29T08:00:00Z'),
        updated_at: Time.zone.parse('2026-08-29T09:00:00Z')
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
      expect(response.parsed_body.dig('data', 'current_stage', 'started_at')).to eq('2026-08-29T09:00:00Z')
      expect(response.parsed_body.dig('data', 'current_stage', 'completed_at')).to be_nil
      expect(response.parsed_body.dig('data', 'timeline', 1, 'name')).to eq(
        WorkflowStage.find_by!(code: 'documents_pending').name_for(locale: :ur)
      )
      expect(response.parsed_body.dig('data', 'timeline', 0, 'completed_at')).to eq('2026-08-29T09:00:00Z')
      expect(response.parsed_body.dig('data', 'timeline', 3, 'code')).to eq('under_verification')
      expect(response.parsed_body.dig('data', 'timeline', 2, 'started_at')).to be_nil
      expect(response.parsed_body.dig('data', 'timeline', 2, 'completed_at')).to be_nil
      expect(response.parsed_body.dig('data', 'completed_count')).to eq(1)
      expect(response.parsed_body.dig('data', 'progress_percentage')).to eq(6)
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

    it 'treats mobilized as terminal completion with 15 completed stages and 100 percent progress' do
      candidate = create(:candidate)
      assignment = create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: WorkflowStage.find_by!(code: 'mobilized'),
        created_at: Time.zone.parse('2026-08-29T08:00:00Z'),
        updated_at: Time.zone.parse('2026-09-12T08:00:00Z')
      )
      previous_stage = WorkflowStage.find_by!(code: 'registered')

      WorkflowStage.order(:position).offset(1).limit(14).each_with_index do |stage, index|
        create(
          :candidate_stage_history,
          candidate_assignment: assignment,
          from_workflow_stage: previous_stage,
          to_workflow_stage: stage,
          occurred_at: Time.zone.parse('2026-08-29T08:00:00Z') + (index + 1).days,
          metadata: {}
        )
        previous_stage = stage
      end

      get '/api/v1/candidate/workflow_state',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'current_stage', 'code')).to eq('mobilized')
      expect(response.parsed_body.dig('data', 'current_stage', 'status')).to eq('completed')
      expect(response.parsed_body.dig('data', 'current_stage', 'started_at')).to be_nil
      expect(response.parsed_body.dig('data', 'current_stage', 'completed_at')).to eq('2026-09-12T08:00:00Z')
      expect(response.parsed_body.dig('data', 'completed_count')).to eq(15)
      expect(response.parsed_body.dig('data', 'progress_percentage')).to eq(100)
    end

    it 'exposes candidate-safe qvc attempts and protection details without internal notes or staff identity' do
      candidate = create(:candidate)
      assignment = create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: WorkflowStage.find_by!(code: 'protected_ready_to_fly')
      )
      actor = create(:user, role: 'mps')
      create(
        :candidate_qvc_attempt,
        candidate_assignment: assignment,
        scheduled_by: actor,
        attempt_number: 1,
        appointment_date: Date.new(2026, 9, 1),
        outcome_code: 'approved',
        outcome_recorded_at: Time.zone.parse('2026-09-02T10:00:00Z'),
        outcome_recorded_by: actor,
        internal_note: 'internal scheduling note'
      )
      create(
        :candidate_protection_record,
        candidate_assignment: assignment,
        appeared_on: Date.new(2026, 9, 10),
        appeared_recorded_at: Time.zone.parse('2026-09-10T10:00:00Z'),
        appeared_recorded_by: actor,
        protected_on: Date.new(2026, 9, 12),
        ready_to_fly_at: Time.zone.parse('2026-09-12T14:00:00Z'),
        ready_recorded_by: actor
      )

      get '/api/v1/candidate/workflow_state',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'qvc_attempts', 0, 'outcome_code')).to eq('approved')
      expect(response.parsed_body.dig('data', 'qvc_attempts', 0, 'status')).to eq('approved')
      expect(response.parsed_body.dig('data', 'protection', 'appeared_on')).to eq('2026-09-10')
      expect(response.parsed_body.dig('data', 'protection', 'ready_to_fly_at')).to eq('2026-09-12T14:00:00Z')
      expect(response.body).not_to include('internal scheduling note')
      expect(response.body).not_to include(actor.public_id)
      expect(response.body).not_to include('scheduled_by')
      expect(response.body).not_to include('outcome_recorded_by')
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

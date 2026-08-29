# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Workflow', type: :request do
  self.use_transactional_tests = false

  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  around do |example|
    IdempotencyKey.delete_all
    AuthenticationEvent.delete_all
    AuditEvent.delete_all
    RefreshToken.delete_all
    CandidateRefreshToken.delete_all
    CandidateStageHistory.delete_all
    CandidateDocumentSubmissionItem.delete_all
    CandidateDocumentSubmission.delete_all
    CandidateDocument.delete_all
    DocumentRequirement.delete_all
    DocumentType.delete_all
    Payment.delete_all
    CandidateAssignment.delete_all
    CandidateSession.delete_all
    Candidate.delete_all
    Session.delete_all
    User.delete_all
    example.run
  ensure
    IdempotencyKey.delete_all
    AuthenticationEvent.delete_all
    AuditEvent.delete_all
    RefreshToken.delete_all
    CandidateRefreshToken.delete_all
    CandidateStageHistory.delete_all
    CandidateDocumentSubmissionItem.delete_all
    CandidateDocumentSubmission.delete_all
    CandidateDocument.delete_all
    DocumentRequirement.delete_all
    DocumentType.delete_all
    Payment.delete_all
    CandidateAssignment.delete_all
    CandidateSession.delete_all
    Candidate.delete_all
    Session.delete_all
    User.delete_all
  end

  def access_token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def candidate_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  def workflow_stage(code)
    WorkflowStage.find_by!(code:)
  end

  def requirement_for(assignment:, code:)
    document_type = document_type_for(code)
    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft
    )
    document_type
  end

  def document_type_for(code)
    DocumentType.find_or_create_by!(code:) do |record|
      record.name_en = code.humanize
      record.name_ur = code.humanize
      record.active = true
      record.requires_number = false
      record.requires_expiry = false
    end
  end

  def create_uploaded_requirement(assignment:, code: 'passport')
    document_type = requirement_for(assignment:, code:)
    create(:candidate_document, candidate_assignment: assignment, document_type:, status_code: 'uploaded')
  end

  def transition_request(candidate:, token:, body:, headers: {})
    post "/api/v1/admin/candidates/#{candidate.public_id}/workflow_transitions",
         params: body,
         headers: { 'Authorization' => "Bearer #{token}" }.merge(headers)
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:cached]
      next if payload[:name] == 'SCHEMA'

      count += 1
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'returns the current workflow state and candidate-safe history for authorized staff readers' do
    actor = create(:user, role: 'hr')
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('documents_pending'))
    create(
      :candidate_stage_history,
      candidate_assignment: assignment,
      from_workflow_stage: workflow_stage('registered'),
      to_workflow_stage: workflow_stage('documents_pending'),
      actor: create(:user, role: 'mps'),
      occurred_at: Time.zone.parse('2026-08-29T09:00:00Z'),
      metadata: { 'source' => 'manual' }
    )

    get "/api/v1/admin/candidates/#{candidate.public_id}/workflow_state",
        headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    expect(response.headers['ETag']).to be_present
    expect(response.parsed_body.dig('data', 'current_stage', 'code')).to eq('documents_pending')

    get "/api/v1/admin/candidates/#{candidate.public_id}/workflow_history",
        headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'history', 0, 'to_stage', 'code')).to eq('documents_pending')
  end

  it 'returns allowed next transitions only for workflow-manage roles' do
    hr = create(:user, role: 'hr')
    mps = create(:user, role: 'mps')
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('documents_pending'))
    create_uploaded_requirement(assignment:)

    get "/api/v1/admin/candidates/#{candidate.public_id}/workflow_transitions",
        headers: { 'Authorization' => "Bearer #{access_token_for(hr)}" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'allowed_next_transitions')).to eq([])

    get "/api/v1/admin/candidates/#{candidate.public_id}/workflow_transitions",
        headers: { 'Authorization' => "Bearer #{access_token_for(mps)}" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'allowed_next_transitions', 0, 'code')).to eq('documents_uploaded')
  end

  it 'performs an idempotent transition, replays duplicate keys, and does not keep failed idempotency rows' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('registered'))
    token = access_token_for(actor)
    body = {
      candidate_workflow_transition: {
        to_stage_code: 'documents_pending',
        expected_current_stage_code: 'registered'
      }
    }

    transition_request(candidate:, token:, headers: { 'Idempotency-Key' => 'wf-1' }, body:)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'workflow', 'current_stage', 'code')).to eq('documents_pending')
    expect(CandidateStageHistory.count).to eq(1)

    transition_request(candidate:, token:, headers: { 'Idempotency-Key' => 'wf-1' }, body:)
    expect(response).to have_http_status(:created)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(CandidateStageHistory.count).to eq(1)

    transition_request(
      candidate:,
      token:,
      headers: { 'Idempotency-Key' => 'wf-2' },
      body: {
        candidate_workflow_transition: {
          to_stage_code: 'documents_uploaded',
          expected_current_stage_code: 'documents_pending'
        }
      }
    )
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('workflow_transition_prerequisite_missing')
    expect(IdempotencyKey.find_by(key_digest: Digest::SHA256.hexdigest('wf-2'))).to be_nil
  end

  it 'rejects stale expectations, candidate tokens, unauthorized roles, and inactive users' do
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('documents_pending'))

    actor = create(:user, role: 'mps')
    transition_request(
      candidate:,
      token: access_token_for(actor),
      headers: { 'Idempotency-Key' => 'wf-stale', 'X-Locale' => 'ur' },
      body: {
        candidate_workflow_transition: {
          to_stage_code: 'documents_uploaded',
          expected_current_stage_code: 'registered'
        }
      }
    )
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('workflow_transition_stale')
    expect(response.headers['Content-Language']).to eq('ur')

    hr = create(:user, role: 'hr')
    transition_request(
      candidate:,
      token: access_token_for(hr),
      headers: { 'Idempotency-Key' => 'wf-hr' },
      body: { candidate_workflow_transition: { to_stage_code: 'documents_uploaded' } }
    )
    expect(response).to have_http_status(:forbidden)

    inactive_mps = create(:user, role: 'mps')
    inactive_token = access_token_for(inactive_mps)
    inactive_mps.update!(active: false)
    transition_request(
      candidate:,
      token: inactive_token,
      headers: { 'Idempotency-Key' => 'wf-inactive' },
      body: { candidate_workflow_transition: { to_stage_code: 'documents_uploaded' } }
    )
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

    transition_request(
      candidate:,
      token: candidate_token_for(candidate),
      headers: { 'Idempotency-Key' => 'wf-candidate' },
      body: { candidate_workflow_transition: { to_stage_code: 'documents_uploaded' } }
    )
    expect(response).to have_http_status(:unauthorized)
  end

  it 'prevents concurrent or stale duplicate transitions from overwriting the winning state' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('registered'))
    token = access_token_for(actor)
    results = Queue.new

    worker = lambda do |key|
      ActiveRecord::Base.connection_pool.with_connection do
        post "/api/v1/admin/candidates/#{candidate.public_id}/workflow_transitions",
             params: {
               candidate_workflow_transition: {
                 to_stage_code: 'documents_pending',
                 expected_current_stage_code: 'registered'
               }
             },
             headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => key }
        results << response.status
      end
    end

    first_thread = Thread.new { worker.call('wf-concurrent-1') }
    second_thread = Thread.new { worker.call('wf-concurrent-2') }
    [first_thread, second_thread].each(&:join)

    expect([results.pop, results.pop]).to contain_exactly(201, 409)
    expect(assignment.reload.current_workflow_stage.code).to eq('documents_pending')
    expect(CandidateStageHistory.count).to eq(1)
  end

  it 'keeps the timeline endpoint query shape bounded as history grows' do
    actor = create(:user, role: 'management')
    token = access_token_for(actor)
    sparse_candidate = create(:candidate)
    sparse_assignment = create(
      :candidate_assignment,
      candidate: sparse_candidate,
      current_workflow_stage: workflow_stage('documents_pending')
    )
    create(
      :candidate_stage_history,
      candidate_assignment: sparse_assignment,
      from_workflow_stage: workflow_stage('registered'),
      to_workflow_stage: workflow_stage('documents_pending'),
      occurred_at: Time.current,
      metadata: {}
    )

    dense_candidate = create(:candidate)
    dense_assignment = create(
      :candidate_assignment,
      candidate: dense_candidate,
      current_workflow_stage: workflow_stage('protected_ready_to_fly')
    )
    previous_stage = workflow_stage('registered')
    WorkflowStage.order(:position).limit(13).offset(1).each do |stage|
      create(
        :candidate_stage_history,
        candidate_assignment: dense_assignment,
        from_workflow_stage: previous_stage,
        to_workflow_stage: stage,
        occurred_at: Time.current,
        metadata: {}
      )
      previous_stage = stage
    end

    sparse_query_count = count_queries do
      get "/api/v1/admin/candidates/#{sparse_candidate.public_id}/workflow_history",
          headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
    end

    dense_query_count = count_queries do
      get "/api/v1/admin/candidates/#{dense_candidate.public_id}/workflow_history",
          headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
    end

    expect(dense_query_count - sparse_query_count).to be <= 1
  end
end

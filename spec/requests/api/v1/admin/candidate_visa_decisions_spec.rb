# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Visa Decisions', type: :request do
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
    CandidateWorkflowEvent.delete_all
    CandidateVisaDecision.delete_all
    CandidateStageHistory.delete_all
    CandidateQvcAttempt.delete_all
    CandidateProtectionRecord.delete_all
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
    CandidateWorkflowEvent.delete_all
    CandidateVisaDecision.delete_all
    CandidateStageHistory.delete_all
    CandidateQvcAttempt.delete_all
    CandidateProtectionRecord.delete_all
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

  def candidate_at_qvc_approved
    candidate = create(:candidate, status_code: 'qvc_completed_outcome_received')
    assignment = create(:candidate_assignment, candidate:,
                                               current_workflow_stage: workflow_stage('qvc_completed_outcome_received'),
                                               qvc_outcome_code: 'approved', qvc_outcome_date: Date.current)
    create_approved_qvc_attempt(assignment)
    [candidate, assignment]
  end

  def create_approved_qvc_attempt(assignment)
    create(:candidate_qvc_attempt, candidate_assignment: assignment, outcome_code: 'approved',
                                   outcome_recorded_at: Time.current, outcome_recorded_by: assignment.created_by,
                                   scheduled_by: assignment.created_by)
  end

  it 'lists visa decisions with private no-store headers for staff' do
    actor = create(:user, role: 'mps')
    candidate, assignment = candidate_at_qvc_approved
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             visa_copy: fixture_upload('test.pdf', 'application/pdf'),
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-list-seed' }
    expect(response).to have_http_status(:created)

    get "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
        headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    expect(response.headers['ETag']).to be_present
    expect(response.parsed_body.dig('data', 'assignment_id')).to eq(assignment.public_id)
    decision = response.parsed_body.dig('data', 'visa_decisions', 0)
    expect(decision.fetch('outcome_code')).to eq('issued')
    expect(decision.fetch('visa_copy_attached')).to be(true)
  end

  it 'returns an empty visa decision collection when the candidate has no current assignment' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'registered')

    get "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
        headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'visa_decisions')).to eq([])
  end

  it 'records an issued visa through the canonical transition path and replays identical retries' do
    actor = create(:user, role: 'mps')
    candidate, assignment = candidate_at_qvc_approved
    token = access_token_for(actor)
    request_params = {
      candidate_visa_decision: {
        outcome_code: 'issued',
        decision_date: '2026-09-05',
        visa_copy: fixture_upload('test.pdf', 'application/pdf'),
        expected_current_stage_code: 'qvc_completed_outcome_received'
      }
    }

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: request_params,
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-issue-1' }

    expect(response).to have_http_status(:created)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    expect(response.parsed_body.dig('data', 'workflow', 'current_stage', 'code')).to eq('visa_issued_or_rejected')
    expect(response.parsed_body.dig('data', 'visa_decision', 'outcome_code')).to eq('issued')
    expect(response.parsed_body.dig('data', 'visa_decision', 'visa_copy_attached')).to be(true)
    expect(CandidateVisaDecision.where(candidate_assignment: assignment).count).to eq(1)
    expect(AuditEvent.where(action_code: 'candidate_visa_decision_recorded').count).to eq(1)
    expect(assignment.reload.current_workflow_stage.code).to eq('visa_issued_or_rejected')

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: request_params.fetch(:candidate_visa_decision).merge(
             visa_copy: fixture_upload('test.pdf', 'application/pdf')
           )
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-issue-1' }

    expect(response).to have_http_status(:created)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(CandidateVisaDecision.where(candidate_assignment: assignment).count).to eq(1)
  end

  it 'records a rejected visa with a structured rejection reason' do
    actor = create(:user, role: 'mps')
    candidate, assignment = candidate_at_qvc_approved
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'rejected',
             rejection_reason_code: 'document_discrepancy',
             decision_date: '2026-09-05',
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-reject-1' }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'visa_decision', 'outcome_code')).to eq('rejected')
    expect(response.parsed_body.dig('data', 'visa_decision', 'rejection_reason_code')).to eq('document_discrepancy')
    expect(response.parsed_body.dig('data', 'visa_decision', 'visa_copy_attached')).to be(false)
    expect(assignment.reload.current_workflow_stage.code).to eq('visa_issued_or_rejected')
  end

  it 'requires a visa copy for an issued outcome' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_at_qvc_approved

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: {
           'Authorization' => "Bearer #{access_token_for(actor)}",
           'Idempotency-Key' => 'visa-missing-copy'
         }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_attachment_missing')
  end

  it 'requires a structured rejection reason for a rejected outcome, localized to Urdu' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_at_qvc_approved

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'rejected',
             decision_date: '2026-09-05',
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: {
           'Authorization' => "Bearer #{access_token_for(actor)}",
           'Idempotency-Key' => 'visa-missing-reason',
           'X-Locale' => 'ur'
         }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.headers['Content-Language']).to eq('ur')
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_visa_decision.rejection_reason_code')
  end

  it 'rejects visa decisions when the QVC outcome was not approved' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'qvc_completed_outcome_received')
    assignment = create(
      :candidate_assignment,
      candidate:,
      current_workflow_stage: workflow_stage('qvc_completed_outcome_received'),
      qvc_outcome_code: 'rejected',
      qvc_outcome_date: Date.current
    )
    create(:candidate_qvc_attempt, candidate_assignment: assignment, outcome_code: 'rejected',
                                   outcome_recorded_at: Time.current, outcome_recorded_by: assignment.created_by,
                                   scheduled_by: assignment.created_by)

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             visa_copy: fixture_upload('test.pdf', 'application/pdf'),
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: {
           'Authorization' => "Bearer #{access_token_for(actor)}",
           'Idempotency-Key' => 'visa-qvc-not-approved'
         }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('workflow_transition_prerequisite_missing')
    expect(response.parsed_body.dig('errors', 0, 'details', 'blocking_reasons')).to include('qvc_rejected')
  end

  it 'requires manage_workflow permission, blocks stale state, and requires expected_current_stage_code' do
    actor = create(:user, role: 'finance')
    candidate, = candidate_at_qvc_approved

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             visa_copy: fixture_upload('test.pdf', 'application/pdf'),
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'visa-forbidden' }

    expect(response).to have_http_status(:forbidden)

    mps_actor = create(:user, role: 'mps')
    token = access_token_for(mps_actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             visa_copy: fixture_upload('test.pdf', 'application/pdf')
           }
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-no-expected-stage' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_visa_decision.expected_current_stage_code')

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             visa_copy: fixture_upload('test.pdf', 'application/pdf'),
             expected_current_stage_code: 'documents_shared_with_qatar_bu'
           }
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-stale' }

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('workflow_transition_stale')
  end

  it 'returns a conflict when the same idempotency key is reused with a different payload' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_at_qvc_approved
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             visa_copy: fixture_upload('test.pdf', 'application/pdf'),
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-drift' }
    expect(response).to have_http_status(:created)

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-06',
             visa_copy: fixture_upload('test.pdf', 'application/pdf'),
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-drift' }

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('idempotency_conflict')
  end

  it 'denies candidate-token access to staff visa decision endpoints' do
    candidate, = candidate_at_qvc_approved

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: {
           'Authorization' => "Bearer #{candidate_token_for(candidate)}",
           'Idempotency-Key' => 'visa-candidate-denied'
         }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'provides short-lived authorized access to the visa copy without exposing a permanent URL' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_at_qvc_approved
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             visa_copy: fixture_upload('test.pdf', 'application/pdf'),
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'visa-for-access' }
    decision_id = response.parsed_body.dig('data', 'visa_decision', 'id')

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions/#{decision_id}/visa_copy_access",
         headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    body = response.parsed_body.fetch('data')
    expect(body.fetch('visa_decision_id')).to eq(decision_id)
    expect(body.fetch('url')).to be_present
    expect(body.fetch('url')).not_to include('rails/active_storage/blobs/redirect')
    expect(Time.iso8601(body.fetch('expires_at'))).to be_within(5.seconds).of(5.minutes.from_now)
    expect(AuditEvent.where(action_code: 'candidate_visa_decision_accessed').count).to eq(1)
  end

  it 'rolls back visa decision creation when audit persistence fails' do
    actor = create(:user, role: 'mps')
    candidate, assignment = candidate_at_qvc_approved

    allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))

    post "/api/v1/admin/candidates/#{candidate.public_id}/visa_decisions",
         params: {
           candidate_visa_decision: {
             outcome_code: 'issued',
             decision_date: '2026-09-05',
             visa_copy: fixture_upload('test.pdf', 'application/pdf'),
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: {
           'Authorization' => "Bearer #{access_token_for(actor)}",
           'Idempotency-Key' => 'visa-audit-rollback'
         }

    expect(response).to have_http_status(:unprocessable_content)
    expect(CandidateVisaDecision.where(candidate_assignment: assignment).count).to eq(0)
    expect(assignment.reload.current_workflow_stage.code).to eq('qvc_completed_outcome_received')
  end
end

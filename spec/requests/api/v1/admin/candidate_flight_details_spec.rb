# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Flight Details', type: :request do
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
    CandidateFlightDetail.delete_all
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
    CandidateFlightDetail.delete_all
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

  def candidate_ready_to_fly
    candidate = create(:candidate, status_code: 'protected_ready_to_fly')
    assignment = create(:candidate_assignment, candidate:,
                                               current_workflow_stage: workflow_stage('protected_ready_to_fly'))
    [candidate, assignment]
  end

  def flight_detail_payload(overrides = {})
    {
      airline: 'Qatar Airways',
      flight_number: 'QR-123',
      sector: 'LHE-DOH',
      flight_date: '2026-09-20T14:30:00Z',
      ticket: fixture_upload('test.pdf', 'application/pdf'),
      expected_current_stage_code: 'protected_ready_to_fly'
    }.merge(overrides)
  end

  it 'shows the flight detail with private no-store headers, empty before recording' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_ready_to_fly

    get "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
        headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    expect(response.parsed_body.dig('data', 'flight_detail')).to be_nil
  end

  it 'records flight details through the canonical transition path and replays identical retries' do
    actor = create(:user, role: 'mps')
    candidate, assignment = candidate_ready_to_fly
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'flight-create-1' }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'workflow', 'current_stage', 'code')).to eq('flight_details_uploaded')
    detail = response.parsed_body.dig('data', 'flight_detail')
    expect(detail.fetch('airline')).to eq('Qatar Airways')
    expect(detail.fetch('flight_number')).to eq('QR-123')
    expect(detail.fetch('sector')).to eq('LHE-DOH')
    expect(detail.fetch('flight_departure_at')).to eq('2026-09-20T14:30:00Z')
    expect(detail.fetch('ticket_attached')).to be(true)
    expect(CandidateFlightDetail.where(candidate_assignment: assignment).count).to eq(1)
    expect(AuditEvent.where(action_code: 'candidate_flight_detail_recorded').count).to eq(1)

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: {
           candidate_flight_detail: flight_detail_payload(ticket: fixture_upload('test.pdf', 'application/pdf'))
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'flight-create-1' }

    expect(response).to have_http_status(:created)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(CandidateFlightDetail.where(candidate_assignment: assignment).count).to eq(1)
  end

  it 'requires the ticket file and validates required fields and flight date format' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_ready_to_fly
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload(ticket: nil) },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'flight-missing-ticket' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_attachment_missing')

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload(flight_date: 'not-a-date') },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'flight-bad-date' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_flight_detail.flight_date')
  end

  it 'mobilizes the candidate through the canonical transition path with immutable audit history' do
    actor = create(:user, role: 'mps')
    candidate, assignment = candidate_ready_to_fly
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'flight-for-mobilize' }
    expect(response).to have_http_status(:created)

    patch "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
          params: {
            candidate_flight_detail: {
              mobilized_on: '2026-09-21',
              expected_current_stage_code: 'flight_details_uploaded'
            }
          },
          headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'mobilize-1' }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'workflow', 'current_stage', 'code')).to eq('mobilized')
    expect(response.parsed_body.dig('data', 'flight_detail', 'mobilized')).to be(true)
    expect(response.parsed_body.dig('data', 'flight_detail', 'mobilized_on')).to eq('2026-09-21')
    expect(assignment.reload.current_workflow_stage.code).to eq('mobilized')
    expect(candidate.reload.status_code).to eq('mobilized')
    expect(AuditEvent.where(action_code: 'candidate_mobilized').count).to eq(1)
    expect(CandidateStageHistory.where(candidate_assignment: assignment).count).to eq(2)

    history_count_before = CandidateStageHistory.count
    audit_count_before = AuditEvent.count

    patch "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
          params: {
            candidate_flight_detail: {
              mobilized_on: '2026-09-22',
              expected_current_stage_code: 'mobilized'
            }
          },
          headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'mobilize-again' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(CandidateStageHistory.count).to eq(history_count_before)
    expect(AuditEvent.count).to eq(audit_count_before)
  end

  it 'rejects a mobilization date before the flight date, deterministically' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_ready_to_fly
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'flight-for-bad-mobilize' }

    patch "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
          params: {
            candidate_flight_detail: {
              mobilized_on: '2026-09-19',
              expected_current_stage_code: 'flight_details_uploaded'
            }
          },
          headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'mobilize-bad-date' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_flight_detail.mobilized_on')
  end

  it 'requires manage_workflow permission and blocks stale mobilization state' do
    actor = create(:user, role: 'finance')
    candidate, = candidate_ready_to_fly

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload },
         headers: { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'flight-forbidden' }

    expect(response).to have_http_status(:forbidden)

    mps_actor = create(:user, role: 'mps')
    token = access_token_for(mps_actor)
    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'flight-then-stale' }
    expect(response).to have_http_status(:created)

    patch "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
          params: {
            candidate_flight_detail: {
              mobilized_on: '2026-09-21',
              expected_current_stage_code: 'protected_ready_to_fly'
            }
          },
          headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'mobilize-stale' }

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('workflow_transition_stale')
  end

  it 'denies candidate-token access to staff flight detail endpoints' do
    candidate, = candidate_ready_to_fly

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload },
         headers: {
           'Authorization' => "Bearer #{candidate_token_for(candidate)}",
           'Idempotency-Key' => 'flight-candidate-denied'
         }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'provides short-lived authorized access to the ticket for both staff and the candidate themselves' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_ready_to_fly
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'flight-for-access' }

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail/ticket_access",
         headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    staff_url = response.parsed_body.dig('data', 'url')
    expect(staff_url).to be_present

    post '/api/v1/candidate/flight_detail/ticket_access',
         headers: { 'Authorization' => "Bearer #{candidate_token_for(candidate)}" }

    expect(response).to have_http_status(:ok)
    candidate_url = response.parsed_body.dig('data', 'url')
    expect(candidate_url).to be_present
    expect(AuditEvent.where(action_code: 'candidate_flight_ticket_accessed').count).to eq(2)
    expect(AuditEvent.where(action_code: 'candidate_flight_ticket_accessed', actor: nil).count).to eq(1)
  end

  it 'lets the candidate view their own flight details but never the ticket URL directly' do
    actor = create(:user, role: 'mps')
    candidate, = candidate_ready_to_fly

    post "/api/v1/admin/candidates/#{candidate.public_id}/flight_detail",
         params: { candidate_flight_detail: flight_detail_payload },
         headers: {
           'Authorization' => "Bearer #{access_token_for(actor)}",
           'Idempotency-Key' => 'flight-for-candidate-show'
         }

    get '/api/v1/candidate/flight_detail', headers: { 'Authorization' => "Bearer #{candidate_token_for(candidate)}" }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body.fetch('data')
    expect(body.fetch('airline')).to eq('Qatar Airways')
    expect(body.fetch('ticket_attached')).to be(true)
    expect(body.keys).not_to include('ticket_url', 'url')
  end
end

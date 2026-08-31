# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate QVC Attempts', type: :request do
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

  # rubocop:disable Metrics/MethodLength
  def create_attempt(candidate:, actor:, stage_code: 'qvc_appointment_booked', outcome_code: nil, no_show: false)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage(stage_code))
    attempt = create(
      :candidate_qvc_attempt,
      candidate_assignment: assignment,
      scheduled_by: actor,
      attempt_number: 1,
      appointment_date: Date.new(2026, 9, 1),
      outcome_code:,
      no_show:,
      outcome_recorded_at: outcome_code.present? || no_show ? Time.zone.parse('2026-09-02T10:00:00Z') : nil,
      outcome_recorded_by: outcome_code.present? || no_show ? actor : nil
    )
    [assignment, attempt]
  end
  # rubocop:enable Metrics/MethodLength

  it 'lists qvc attempts with private no-store headers for staff' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'qvc_completed_outcome_received')
    assignment, attempt = create_attempt(
      candidate:,
      actor:,
      stage_code: 'qvc_completed_outcome_received',
      outcome_code: 'approved'
    )

    get "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts",
        headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    expect(response.headers['ETag']).to be_present
    expect(response.parsed_body.dig('data', 'candidate_id')).to eq(candidate.public_id)
    expect(response.parsed_body.dig('data', 'assignment_id')).to eq(assignment.public_id)
    expect(response.parsed_body.dig('data', 'qvc_attempts', 0, 'id')).to eq(attempt.public_id)
  end

  it 'returns an empty qvc attempt collection when the candidate has no current assignment' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'registered')

    get "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts",
        headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'assignment_id')).to be_nil
    expect(response.parsed_body.dig('data', 'qvc_attempts')).to eq([])
    expect(response.parsed_body.dig('data', 'updated_at')).to be_nil
  end

  it 'schedules the first qvc appointment through the canonical transition path and replays identical retries' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'documents_shared_with_qatar_bu')
    assignment = create(
      :candidate_assignment,
      candidate:,
      current_workflow_stage: workflow_stage('documents_shared_with_qatar_bu')
    )
    token = access_token_for(actor)
    body = {
      candidate_qvc_attempt: {
        appointment_date: '2026-09-01',
        expected_current_stage_code: 'documents_shared_with_qatar_bu'
      }
    }

    post "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts",
         params: body,
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'qvc-schedule-1' }

    expect(response).to have_http_status(:created)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    expect(response.parsed_body.dig('data', 'workflow', 'current_stage', 'code')).to eq('qvc_appointment_booked')
    expect(response.parsed_body.dig('data', 'workflow', 'qvc_attempts', 0, 'appointment_date')).to eq('2026-09-01')
    expect(CandidateQvcAttempt.where(candidate_assignment: assignment).count).to eq(1)
    expect(AuditEvent.where(action_code: 'candidate_qvc_attempt_scheduled').count).to eq(1)

    post "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts",
         params: body,
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'qvc-schedule-1' }

    expect(response).to have_http_status(:created)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(CandidateQvcAttempt.where(candidate_assignment: assignment).count).to eq(1)

    post "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts",
         params: {
           candidate_qvc_attempt: body.fetch(:candidate_qvc_attempt).merge(note: 'drift')
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'qvc-schedule-1' }

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('idempotency_conflict')
  end

  it 'validates appointment dates and localizes the response' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'documents_shared_with_qatar_bu')
    create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('documents_shared_with_qatar_bu'))

    post "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts",
         params: {
           candidate_qvc_attempt: {
             appointment_date: 'not-a-date',
             expected_current_stage_code: 'documents_shared_with_qatar_bu'
           }
         },
         headers: {
           'Authorization' => "Bearer #{access_token_for(actor)}",
           'Idempotency-Key' => 'qvc-invalid-date',
           'X-Locale' => 'ur'
         }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.headers['Content-Language']).to eq('ur')
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_qvc_attempt.appointment_date')
  end

  it 'rejects conflicting no_show and unsupported outcome values' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'qvc_appointment_booked')
    _, attempt = create_attempt(candidate:, actor:)
    token = access_token_for(actor)

    patch "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts/#{attempt.public_id}",
          params: {
            candidate_qvc_attempt: {
              outcome_code: 'approved',
              no_show: true,
              expected_current_stage_code: 'qvc_appointment_booked'
            }
          },
          headers: {
            'Authorization' => "Bearer #{token}",
            'Idempotency-Key' => 'qvc-no-show-conflict'
          }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_qvc_attempt.outcome_code')

    patch "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts/#{attempt.public_id}",
          params: {
            candidate_qvc_attempt: {
              outcome_code: 'invalid-value',
              expected_current_stage_code: 'qvc_appointment_booked'
            }
          },
          headers: {
            'Authorization' => "Bearer #{token}",
            'Idempotency-Key' => 'qvc-invalid-outcome'
          }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_qvc_attempt.outcome_code')
  end

  it 'records approved, re_medical, rejected, and no_show outcomes with server timestamps and no duplicate attempts' do
    actor = create(:user, role: 'mps')
    token = access_token_for(actor)

    {
      'approved' => { expected_stage: 'qvc_completed_outcome_received', no_show: false },
      're_medical' => { expected_stage: 'qvc_completed_outcome_received', no_show: false },
      'rejected' => { expected_stage: 'qvc_completed_outcome_received', no_show: false },
      nil => { expected_stage: 'qvc_appointment_booked', no_show: true }
    }.each_with_index do |(outcome_code, expectation), index|
      candidate = create(:candidate, status_code: 'qvc_appointment_booked')
      assignment, attempt = create_attempt(candidate:, actor:)

      travel_to(Time.zone.parse("2026-08-30T12:0#{index}:00Z")) do
        patch "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts/#{attempt.public_id}",
              params: {
                candidate_qvc_attempt: {
                  outcome_code:,
                  no_show: expectation.fetch(:no_show),
                  expected_current_stage_code: 'qvc_appointment_booked',
                  note: 'staff only note'
                }
              },
              headers: {
                'Authorization' => "Bearer #{token}",
                'Idempotency-Key' => "qvc-outcome-#{index}"
              }
      end

      expect(response).to have_http_status(:ok)
      if expectation.fetch(:expected_stage) == 'qvc_completed_outcome_received'
        qvc_attempt = response.parsed_body.fetch('data').fetch('workflow').fetch('qvc_attempts').last
        expect(qvc_attempt.fetch('status')).to eq(outcome_code)
        expect(qvc_attempt.fetch('outcome_recorded_at')).to eq("2026-08-30T12:0#{index}:00Z")
      else
        expect(response.parsed_body.dig('data', 'qvc_attempt', 'status')).to eq('no_show')
        expect(response.parsed_body.dig('data', 'qvc_attempt', 'outcome_recorded_at')).to eq(
          "2026-08-30T12:0#{index}:00Z"
        )
      end
      expect(assignment.reload.current_workflow_stage.code).to eq(expectation.fetch(:expected_stage))
      expect(candidate.reload.status_code).to eq(expectation.fetch(:expected_stage))
      expect(CandidateQvcAttempt.where(candidate_assignment: assignment).count).to eq(1)
    end
  end

  it 'supports re_medical follow-up attempts without overwriting prior attempts ' \
     'and blocks stale or unauthorized updates' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'qvc_completed_outcome_received')
    assignment = create(
      :candidate_assignment,
      candidate:,
      current_workflow_stage: workflow_stage('qvc_completed_outcome_received'),
      qvc_outcome_code: 're_medical',
      qvc_outcome_date: Date.new(2026, 9, 2)
    )
    prior_attempt = create(
      :candidate_qvc_attempt,
      candidate_assignment: assignment,
      scheduled_by: actor,
      attempt_number: 1,
      appointment_date: Date.new(2026, 9, 1),
      outcome_code: 're_medical',
      outcome_recorded_at: Time.zone.parse('2026-09-02T10:00:00Z'),
      outcome_recorded_by: actor,
      internal_note: 'previous note'
    )
    token = access_token_for(actor)

    post "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts",
         params: {
           candidate_qvc_attempt: {
             appointment_date: '2026-09-05',
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'qvc-remedical-follow-up' }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'qvc_attempt', 'attempt_number')).to eq(2)
    expect(assignment.reload.current_workflow_stage.code).to eq('qvc_completed_outcome_received')
    expect(prior_attempt.reload.outcome_code).to eq('re_medical')

    follow_up_id = response.parsed_body.dig('data', 'qvc_attempt', 'id')
    patch "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts/#{follow_up_id}",
          params: {
            candidate_qvc_attempt: {
              outcome_code: 'approved',
              expected_current_stage_code: 'qvc_completed_outcome_received'
            }
          },
          headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'qvc-remedical-approved' }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'workflow', 'current_stage', 'code'))
      .to eq('qvc_completed_outcome_received')
    expect(response.parsed_body.dig('data', 'qvc_attempt', 'outcome_code')).to eq('approved')
    expect(assignment.reload.qvc_outcome_code).to eq('approved')
    expect(CandidateQvcAttempt.where(candidate_assignment: assignment).count).to eq(2)

    patch "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts/#{follow_up_id}",
          params: {
            candidate_qvc_attempt: {
              outcome_code: 'approved',
              expected_current_stage_code: 'documents_shared_with_qatar_bu'
            }
          },
          headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'qvc-remedical-stale' }

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('workflow_transition_stale')

    patch "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts/#{follow_up_id}",
          params: {
            candidate_qvc_attempt: {
              outcome_code: 'approved',
              expected_current_stage_code: 'qvc_completed_outcome_received'
            }
          },
          headers: {
            'Authorization' => "Bearer #{candidate_token_for(candidate)}",
            'Idempotency-Key' => 'qvc-candidate-denied'
          }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rolls back qvc attempt creation when audit persistence fails' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'qvc_completed_outcome_received')
    assignment = create(
      :candidate_assignment,
      candidate:,
      current_workflow_stage: workflow_stage('qvc_completed_outcome_received'),
      qvc_outcome_code: 're_medical',
      qvc_outcome_date: Date.new(2026, 9, 2)
    )
    create(
      :candidate_qvc_attempt,
      candidate_assignment: assignment,
      scheduled_by: actor,
      attempt_number: 1,
      appointment_date: Date.new(2026, 9, 1),
      outcome_code: 're_medical',
      outcome_recorded_at: Time.zone.parse('2026-09-02T10:00:00Z'),
      outcome_recorded_by: actor
    )

    allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))

    post "/api/v1/admin/candidates/#{candidate.public_id}/qvc_attempts",
         params: {
           candidate_qvc_attempt: {
             appointment_date: '2026-09-05',
             expected_current_stage_code: 'qvc_completed_outcome_received'
           }
         },
         headers: {
           'Authorization' => "Bearer #{access_token_for(actor)}",
           'Idempotency-Key' => 'qvc-audit-rollback'
         }

    expect(response).to have_http_status(:unprocessable_content)
    expect(CandidateQvcAttempt.where(candidate_assignment: assignment).count).to eq(1)
    expect(assignment.reload.current_workflow_stage.code).to eq('qvc_completed_outcome_received')
  end
end

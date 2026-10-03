# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Medical Results', type: :request do
  before { ensure_staff_authorization_reference_data! }

  def access_token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def record(candidate, token, idempotency_key, **fields)
    post "/api/v1/admin/candidates/#{candidate.public_id}/medical_results",
         params: { candidate_medical_result: fields },
         headers: { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => idempotency_key }
  end

  let(:candidate) { create(:candidate, status_code: 'medical_appointment') }
  let!(:assignment) do
    create(:candidate_assignment, candidate:, country: process_country(:qatar),
                                  current_workflow_stage: WorkflowStage.find_by!(code: 'medical_appointment'))
  end

  it 'records an unfit result into the medical stage, re-decides it fit, and lists both for staff' do
    token = access_token_for(create(:user, role: 'mps'))

    record(candidate, token, 'medical-1', outcome_code: 'unfit', result_date: '2026-08-22', note: 'Re-test in 2 weeks',
                                          expected_current_stage_code: 'medical_appointment')

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'workflow', 'current_stage', 'code')).to eq('medical_fit')
    expect(response.parsed_body.dig('data', 'medical_result')).to include('outcome_code' => 'unfit',
                                                                          're_decision' => false)

    record(candidate, token, 'medical-2', outcome_code: 'fit', result_date: '2026-09-05',
                                          expected_current_stage_code: 'medical_fit')

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data',
                                    'medical_result')).to include('outcome_code' => 'fit', 're_decision' => true)
    expect(response.parsed_body.dig('data', 'workflow', 'outcomes', 'medical', 'outcome_code')).to eq('fit')

    get "/api/v1/admin/candidates/#{candidate.public_id}/medical_results",
        headers: { 'Authorization' => "Bearer #{token}" }

    results = response.parsed_body.dig('data', 'medical_results')
    expect(results.pluck('outcome_code')).to eq(%w[fit unfit])
    expect(results.last).to include('note' => 'Re-test in 2 weeks', 'recorded_by' => include('role' => 'mps'))
  end

  it 'rejects a stale expected stage and an invalid outcome' do
    token = access_token_for(create(:user, role: 'mps'))

    record(candidate, token, 'medical-stale', outcome_code: 'fit', result_date: '2026-08-22',
                                              expected_current_stage_code: 'verified')
    expect(response).to have_http_status(:conflict)

    record(candidate, token, 'medical-bad', outcome_code: 'great', result_date: '2026-08-22',
                                            expected_current_stage_code: 'medical_appointment')
    expect(response).to have_http_status(:unprocessable_content)
    expect(assignment.candidate_medical_results.count).to eq(0)
  end

  it 'is forbidden for staff without manage_workflow' do
    record(candidate, access_token_for(create(:user, role: 'finance')), 'medical-forbidden',
           outcome_code: 'fit', result_date: '2026-08-22', expected_current_stage_code: 'medical_appointment')

    expect(response).to have_http_status(:forbidden)
  end
end

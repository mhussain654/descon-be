# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidates', type: :request do
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

  def strip_permission!(role_code, permission_code)
    RolePermission.joins(:role, :permission)
                  .find_by!(roles: { code: role_code }, permissions: { code: permission_code })
                  .destroy!
  end

  def workflow_stage(code)
    WorkflowStage.find_by!(code:)
  end

  def create_candidate_params(overrides = {})
    {
      full_name: 'Jane Applicant',
      cnic: '42101-1234567-1',
      mobile_number: '+923001234567',
      preferred_locale: 'en',
      country_code: Country.first.code,
      project_code: Project.first.code,
      craft_code: Craft.first.code,
      reference_number: 'DES-REQ0001'
    }.merge(overrides)
  end

  describe 'POST /api/v1/admin/candidates' do
    it 'creates a candidate and its initial assignment, auto-advancing to documents_pending' do
      actor = create(:user, role: 'hr')

      post '/api/v1/admin/candidates',
           params: { candidate: create_candidate_params },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}",
                      'Idempotency-Key' => 'candidate-create-1' }

      expect(response).to have_http_status(:created)
      data = response.parsed_body.fetch('data')
      expect(data.fetch('full_name')).to eq('Jane Applicant')
      expect(data.fetch('cnic')).to eq('42101-1234567-1')
      expect(data.fetch('candidate_status')).to eq('documents_pending')
      expect(data.dig('assignment', 'reference_number')).to eq('DES-REQ0001')
      expect(data.dig('assignment', 'current_workflow_stage', 'code')).to eq('documents_pending')
      expect(AuditEvent.where(action_code: 'candidate_created').count).to eq(1)
    end

    it 'replays an identical retry under the same idempotency key without creating a second candidate' do
      actor = create(:user, role: 'hr')
      token = access_token_for(actor)
      params = { candidate: create_candidate_params }

      retry_headers = { 'Authorization' => "Bearer #{token}", 'Idempotency-Key' => 'candidate-create-retry' }

      post '/api/v1/admin/candidates', params:, headers: retry_headers
      expect(response).to have_http_status(:created)

      post '/api/v1/admin/candidates', params:, headers: retry_headers
      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(Candidate.where(cnic: '42101-1234567-1').count).to eq(1)
    end

    it 'is forbidden for a staff member without manage_candidates' do
      actor = create(:user, role: 'mps')

      post '/api/v1/admin/candidates',
           params: { candidate: create_candidate_params },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}",
                      'Idempotency-Key' => 'candidate-create-forbidden' }

      expect(response).to have_http_status(:forbidden)
      expect(Candidate.count).to eq(0)
    end

    it 'rejects a duplicate CNIC clearly' do
      actor = create(:user, role: 'hr')
      create(:candidate, cnic: '42101-1234567-1')

      post '/api/v1/admin/candidates',
           params: { candidate: create_candidate_params(reference_number: 'DES-REQ0002') },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}",
                      'Idempotency-Key' => 'candidate-create-dup-cnic' }

      expect(response).to have_http_status(:unprocessable_content)
      error = response.parsed_body.dig('errors', 0)
      expect(error.fetch('code')).to eq('duplicate_cnic')
      expect(error.fetch('field')).to eq('cnic')
    end

    it 'rejects a duplicate passport number clearly' do
      actor = create(:user, role: 'hr')
      create(:candidate, passport_number: 'AB123456')

      post '/api/v1/admin/candidates',
           params: { candidate: create_candidate_params(passport_number: 'ab123456') },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}",
                      'Idempotency-Key' => 'candidate-create-dup-passport' }

      expect(response).to have_http_status(:unprocessable_content)
      error = response.parsed_body.dig('errors', 0)
      expect(error.fetch('code')).to eq('duplicate_passport_number')
      expect(error.fetch('field')).to eq('passport_number')
    end

    it 'rejects a duplicate reference number clearly' do
      actor = create(:user, role: 'hr')
      other_candidate = create(:candidate)
      create(:candidate_assignment, candidate: other_candidate, reference_number: 'DES-REQ0001',
                                    current_workflow_stage: create(:workflow_stage, :registered))

      post '/api/v1/admin/candidates',
           params: { candidate: create_candidate_params(cnic: '42101-7654321-2') },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}",
                      'Idempotency-Key' => 'candidate-create-dup-ref' }

      expect(response).to have_http_status(:unprocessable_content)
      error = response.parsed_body.dig('errors', 0)
      expect(error.fetch('code')).to eq('duplicate_reference_number')
      expect(error.fetch('field')).to eq('reference_number')
    end

    it 'maps an unknown project code to the correct field' do
      actor = create(:user, role: 'hr')

      post '/api/v1/admin/candidates',
           params: { candidate: create_candidate_params(project_code: 'not_a_real_project') },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}",
                      'Idempotency-Key' => 'candidate-create-unknown-project' }

      expect(response).to have_http_status(:unprocessable_content)
      error = response.parsed_body.dig('errors', 0)
      expect(error.fetch('field')).to eq('project_code')
    end

    it 'requires the full name' do
      actor = create(:user, role: 'hr')

      post '/api/v1/admin/candidates',
           params: { candidate: create_candidate_params(full_name: '') },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}",
                      'Idempotency-Key' => 'candidate-create-missing-name' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('full_name')
    end

    it 'localizes the duplicate CNIC message to Urdu' do
      actor = create(:user, role: 'hr')
      create(:candidate, cnic: '42101-1234567-1')

      post '/api/v1/admin/candidates',
           params: { candidate: create_candidate_params(reference_number: 'DES-REQ0003') },
           headers: {
             'Authorization' => "Bearer #{access_token_for(actor)}",
             'Idempotency-Key' => 'candidate-create-dup-cnic-ur',
             'X-Locale' => 'ur'
           }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'message')).to include('شناختی کارڈ')
    end
  end

  describe 'GET /api/v1/admin/candidates/:id' do
    it 'returns the full unmasked candidate detail with private no-store headers' do
      actor = create(:user, role: 'mps')
      candidate = create(:candidate, passport_number: 'AB123456')
      assignment = create(:candidate_assignment, candidate:,
                                                 current_workflow_stage: create(:workflow_stage, :registered))

      get "/api/v1/admin/candidates/#{candidate.public_id}",
          headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.headers['ETag']).to be_present
      data = response.parsed_body.fetch('data')
      expect(data.fetch('cnic')).to eq(candidate.cnic)
      expect(data.fetch('passport_number')).to eq('AB123456')
      expect(data.dig('assignment', 'reference_number')).to eq(assignment.reference_number)
    end

    it 'is not found, not forbidden, for a role lacking view/manage_candidates (excluded by policy scope first)' do
      strip_permission!('finance', 'view_candidates')
      actor = create(:user, role: 'finance')
      candidate = create(:candidate)

      get "/api/v1/admin/candidates/#{candidate.public_id}",
          headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns not found for an unknown candidate id' do
      actor = create(:user, role: 'mps')

      get "/api/v1/admin/candidates/#{SecureRandom.uuid}",
          headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects a candidate session token -- this endpoint is staff-only' do
      candidate = create(:candidate)

      get "/api/v1/admin/candidates/#{candidate.public_id}",
          headers: { 'Authorization' => "Bearer #{candidate_token_for(candidate)}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/candidates/:id' do
    it "updates the candidate's own profile fields" do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { full_name: 'Updated Name', mobile_number: '+923001112222' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      expect(data.fetch('full_name')).to eq('Updated Name')
      expect(data.fetch('mobile_number')).to eq('+923001112222')
      expect(AuditEvent.where(action_code: 'candidate_updated').count).to eq(1)
    end

    it 'clears the passport number when sent blank' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate, passport_number: 'AB123456')
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { passport_number: '' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'passport_number')).to be_nil
    end

    it 'rejects blanking the required full_name' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { full_name: '' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('full_name')
    end

    it 'rejects an invalid mobile number' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { mobile_number: 'not-a-number' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('mobile_number')
    end

    it 'rejects an unsupported preferred_locale' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { preferred_locale: 'fr' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('preferred_locale')
    end

    it 'maps an unknown country/project/craft code to the correct field while still at documents_pending' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('documents_pending'))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { country_code: 'not_a_real_country' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('country_code')
    end

    it 'rejects a malformed expected_updated_at as a validation error, not a stale conflict' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { full_name: 'New Name', expected_updated_at: 'not-a-timestamp' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('expected_updated_at')
    end

    it 'rejects a duplicate passport number on update' do
      actor = create(:user, role: 'hr')
      create(:candidate, passport_number: 'CD999999')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { passport_number: 'cd999999' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('duplicate_passport_number')
    end

    it 'allows editing project/country/craft while the assignment has not moved past documents_pending' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('documents_pending'))
      new_project = create(:project)

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { project_code: new_project.code } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'assignment', 'project', 'code')).to eq(new_project.code)
    end

    it 'locks project/country/craft once a document has been uploaded' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: workflow_stage('documents_uploaded'))
      new_craft = create(:craft)

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { craft_code: new_craft.code } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:unprocessable_content)
      error = response.parsed_body.dig('errors', 0)
      expect(error.fetch('code')).to eq('candidate_assignment_field_locked')
      expect(error.fetch('field')).to eq('craft_code')
    end

    it 'rejects a stale update when expected_updated_at does not match the current state' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { full_name: 'Stale Attempt', expected_updated_at: 1.hour.ago.utc.iso8601 } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('stale_candidate')
    end

    it 'accepts a matching expected_updated_at' do
      actor = create(:user, role: 'hr')
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:,
                                                 current_workflow_stage: create(:workflow_stage, :registered))
      expected = [candidate.updated_at, assignment.updated_at].max.utc.iso8601

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { full_name: 'Fresh Update', expected_updated_at: expected } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'full_name')).to eq('Fresh Update')
    end

    it 'is forbidden for a staff member without manage_candidates' do
      actor = create(:user, role: 'mps')
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:, current_workflow_stage: create(:workflow_stage, :registered))

      patch "/api/v1/admin/candidates/#{candidate.public_id}",
            params: { candidate: { full_name: 'Blocked Update' } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end

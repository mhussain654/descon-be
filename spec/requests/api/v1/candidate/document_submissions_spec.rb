# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Document Submissions', type: :request do
  def existing_or_create_document_type(code)
    DocumentType.find_or_create_by!(code:) do |document_type|
      document_type.name_en = code.humanize
      document_type.name_ur = code.humanize
      document_type.active = true
      document_type.requires_number = false
      document_type.requires_expiry = false
    end
  end

  def candidate_access_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  def candidate_auth_headers(candidate, extra_headers = {})
    { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }.merge(extra_headers)
  end

  def create_requirement(assignment:, code:, required: true)
    document_type = existing_or_create_document_type(code)
    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required:
    )
    document_type
  end

  def pcc_code
    CandidateDocument::PCC_REQUIREMENT_CODE
  end

  def resolved_required_requirements(candidate:, assignment:)
    Candidates::Documents::RequirementResolver.call(candidate:, assignment:).select(&:required)
  end

  def create_required_documents(candidate:, assignment:, default_status: 'uploaded', overrides: {})
    resolved_required_requirements(candidate:, assignment:).each do |requirement|
      attributes = overrides.fetch(requirement.document_type.code, {})
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: requirement.document_type,
        status_code: attributes.fetch(:status_code, default_status),
        **attributes.except(:status_code)
      )
    end
  end

  def without_active_document_requirements
    active_requirements = DocumentRequirement.where(active: true).to_a
    active_requirements.each { |requirement| requirement.update!(active: false) }
    yield
  ensure
    active_requirements&.each { |requirement| requirement.update!(active: true) }
  end

  describe 'POST /api/v1/candidate/document_submissions' do
    it 'submits the authenticated candidate documents and replays the same key safely' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      create_requirement(assignment:, code: 'passport')
      required_total = resolved_required_requirements(candidate:, assignment:).count
      create_required_documents(candidate:, assignment:)
      headers = candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-submission-1')

      post '/api/v1/candidate/document_submissions', headers: headers

      expect(response).to have_http_status(:created)
      first_submission_id = response.parsed_body.dig('data', 'submission_id')
      expect(response.parsed_body.dig('data', 'documents', 'pending_review')).to eq(required_total)
      expect(response.parsed_body.dig('data', 'message')).to eq(I18n.t('api.candidate_document_submissions.submitted'))

      expect do
        post '/api/v1/candidate/document_submissions', headers: headers
      end.not_to change(CandidateDocumentSubmission, :count)

      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(response.parsed_body.dig('data', 'submission_id')).to eq(first_submission_id)
    end

    it 'replays the same result after a renewed access token for the same candidate' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      create_requirement(assignment:, code: 'passport')
      create_required_documents(candidate:, assignment:)
      headers = { 'Idempotency-Key' => 'candidate-submission-renewed-token' }

      post '/api/v1/candidate/document_submissions', headers: candidate_auth_headers(candidate, headers)
      first_submission_id = response.parsed_body.dig('data', 'submission_id')

      post '/api/v1/candidate/document_submissions', headers: candidate_auth_headers(candidate, headers)

      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(response.parsed_body.dig('data', 'submission_id')).to eq(first_submission_id)
    end

    it 'keeps the same key isolated between candidates' do
      first_candidate = create(:candidate)
      first_assignment = create(:candidate_assignment, candidate: first_candidate)
      second_candidate = create(:candidate)
      second_assignment = create(:candidate_assignment, candidate: second_candidate)
      create_requirement(assignment: first_assignment, code: 'passport')
      create_requirement(assignment: second_assignment, code: 'passport')
      create_required_documents(candidate: first_candidate, assignment: first_assignment)
      create_required_documents(candidate: second_candidate, assignment: second_assignment)

      post '/api/v1/candidate/document_submissions',
           headers: candidate_auth_headers(first_candidate, 'Idempotency-Key' => 'shared-submission-key')
      post '/api/v1/candidate/document_submissions',
           headers: candidate_auth_headers(second_candidate, 'Idempotency-Key' => 'shared-submission-key')

      expect(response).to have_http_status(:created)
      expect(CandidateDocumentSubmission.count).to eq(2)
    end

    it 'returns blocking details for incomplete and rejected submissions' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      create_requirement(assignment:, code: 'passport')

      post '/api/v1/candidate/document_submissions', headers: candidate_auth_headers(candidate, 'X-Locale' => 'ur')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('documents_incomplete')
      expect(response.parsed_body.dig('errors', 0, 'details', 'blocking_requirements', 0, 'reason')).to eq('missing')
      expect(response.headers['Content-Language']).to eq('ur')

      create_required_documents(
        candidate:,
        assignment:,
        overrides: { 'passport' => { status_code: 'rejected', verified_by: create(:user), verified_at: Time.current,
                                     rejection_reason: 'blurred' } }
      )

      post '/api/v1/candidate/document_submissions', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('documents_rejected')
    end

    it 'blocks submission when the required PCC has expired' do
      travel_to(Time.zone.local(2026, 8, 28, 12, 0, 0)) do
        candidate = create(:candidate)
        assignment = create(:candidate_assignment, candidate:)
        pcc = create_requirement(assignment:, code: pcc_code)
        create_required_documents(
          candidate:,
          assignment:,
          overrides: {
            pcc.code => { issued_on: Date.new(2026, 1, 1) }
          }
        )

        post '/api/v1/candidate/document_submissions', headers: candidate_auth_headers(candidate, 'X-Locale' => 'ur')

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig('errors', 0, 'code')).to eq('documents_incomplete')
        blocking_requirement = response.parsed_body.dig('errors', 0, 'details', 'blocking_requirements').find do |item|
          item['requirement_code'] == pcc_code
        end
        expect(blocking_requirement).to include('reason' => 'expired')
        expect(response.headers['Content-Language']).to eq('ur')
      end
    end

    it 'rejects no-assignment, no-requirements, inactive-candidate, and staff-token cases safely' do
      candidate = create(:candidate)
      post '/api/v1/candidate/document_submissions', headers: candidate_auth_headers(candidate)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('no_current_assignment')

      candidate_with_assignment = create(:candidate)
      create(:candidate_assignment, candidate: candidate_with_assignment)
      without_active_document_requirements do
        post '/api/v1/candidate/document_submissions', headers: candidate_auth_headers(candidate_with_assignment)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig('errors', 0, 'code')).to eq('no_document_requirements')
      end

      inactive_candidate = create(:candidate, active: false)
      post '/api/v1/candidate/document_submissions',
           headers: { 'Authorization' => "Bearer #{candidate_access_token_for(inactive_candidate)}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin', password: 'Password123!')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
      post '/api/v1/candidate/document_submissions',
           headers: { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

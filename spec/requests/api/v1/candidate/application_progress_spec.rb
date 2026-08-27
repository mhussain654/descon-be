# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Application Progress', type: :request do
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

  describe 'GET /api/v1/candidate/application_progress' do
    it 'returns no_assignment progress for a candidate without a current assignment' do
      candidate = create(:candidate)

      get '/api/v1/candidate/application_progress', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'documents', 'submission_state')).to eq('no_assignment')
      expect(response.parsed_body.dig('data', 'documents', 'required_total')).to eq(0)
    end

    it 'returns blocking requirements and localized names for the authenticated candidate only' do
      candidate = create(:candidate, preferred_locale: 'ur')
      assignment = create(:candidate_assignment, candidate:)
      other_candidate = create(:candidate)
      other_assignment = create(:candidate_assignment, candidate: other_candidate)
      passport = create_requirement(assignment:, code: 'passport')
      create_requirement(assignment: other_assignment, code: 'cv')
      create(:candidate_document, candidate_assignment: assignment, document_type: passport, status_code: 'uploaded')

      get '/api/v1/candidate/application_progress',
          params: { candidate_id: other_candidate.public_id },
          headers: candidate_auth_headers(candidate, 'X-Locale' => 'ur')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'documents', 'required_total')).to eq(1)
      expect(response.parsed_body.dig('data', 'documents', 'submission_state')).to eq('ready')
      expect(response.parsed_body.dig('data', 'current_workflow_stage', 'name')).to be_present
      expect(response.headers['Content-Language']).to eq('ur')
    end

    it 'rejects inactive candidates and staff tokens' do
      candidate = create(:candidate, active: false)

      get '/api/v1/candidate/application_progress',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin', password: 'Password123!')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }

      get '/api/v1/candidate/application_progress',
          headers: { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

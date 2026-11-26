# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Uploaded Documents', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let!(:unsubmitted) { create(:candidate_document, candidate_assignment: assignment, status_code: 'uploaded') }
  let!(:submitted) do
    create(:candidate_document, candidate_assignment: assignment, status_code: 'under_verification').tap do |document|
      submission = create(:candidate_document_submission, candidate_assignment: assignment)
      create(:candidate_document_submission_item, candidate_document_submission: submission,
                                                  candidate_document: document)
    end
  end

  def headers_for(role)
    user = create(:user, role:)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def list(role)
    get "/api/v1/admin/candidates/#{candidate.public_id}/uploaded_documents", headers: headers_for(role)
  end

  describe 'GET /api/v1/admin/candidates/:candidate_id/uploaded_documents' do
    it 'lists every current document for a developer, submitted or not, with its files' do
      list('developer')

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')
      rows = response.parsed_body.fetch('data').index_by { |row| row.fetch('id') }
      expect(rows.fetch(unsubmitted.public_id)).to include('submitted' => false, 'status' => 'uploaded')
      expect(rows.fetch(submitted.public_id)).to include('submitted' => true, 'status' => 'under_verification')
      expect(rows.fetch(unsubmitted.public_id).dig('files', 0)).to include('original_filename' => 'document.pdf')
    end

    it 'leaves out replaced (superseded) versions' do
      unsubmitted.update!(superseded_at: Time.current)

      list('developer')

      expect(response.parsed_body.fetch('data').pluck('id')).to eq([submitted.public_id])
    end

    it 'is developer-only' do
      %w[admin hr mps].each do |role|
        list(role)

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_access_forbidden')
      end
    end

    it 'rejects an unauthenticated request' do
      get "/api/v1/admin/candidates/#{candidate.public_id}/uploaded_documents"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/uploaded_documents/:id/access' do
    def access(role, document_id = unsubmitted.public_id)
      post "/api/v1/admin/candidates/#{candidate.public_id}/uploaded_documents/#{document_id}/access",
           headers: headers_for(role)
    end

    it 'gives a developer a short-lived link to an unsubmitted document and records the access' do
      expect { access('developer') }.to change {
        AuditEvent.where(action_code: 'candidate_document_accessed').count
      }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'url')).to be_present
      expect(AuditEvent.last.metadata.fetch('requirement_code')).to eq(unsubmitted.document_type.code)
    end

    it "is not found for another candidate's document" do
      other = create(:candidate_document)

      access('developer', other.public_id)

      expect(response).to have_http_status(:not_found)
    end

    it 'is developer-only' do
      access('admin')

      expect(response).to have_http_status(:forbidden)
    end
  end
end

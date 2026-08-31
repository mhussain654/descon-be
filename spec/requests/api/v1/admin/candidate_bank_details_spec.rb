# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Bank Details', type: :request do
  before do
    ensure_staff_authorization_reference_data!
  end

  def access_token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def candidate_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  describe 'GET /api/v1/admin/candidates/:candidate_id/bank_details' do
    it 'returns masked details for view-only staff and unmasked details for payment-authorized staff' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      create(:candidate_bank_detail, candidate_assignment: assignment, account_number: 'PK24SCBL0000001123456702')

      management = create(:user, role: 'management')
      get "/api/v1/admin/candidates/#{candidate.public_id}/bank_details",
          headers: { 'Authorization' => "Bearer #{access_token_for(management)}", 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Language']).to eq('ur')
      expect(response.parsed_body.dig('data', 'account_number')).to end_with('6702')
      expect(response.parsed_body.dig('data', 'account_number')).not_to eq('PK24SCBL0000001123456702')
      expect(AuditEvent.where(action_code: 'candidate_bank_detail_viewed_unmasked')).to be_empty

      finance = create(:user, role: 'finance')
      get "/api/v1/admin/candidates/#{candidate.public_id}/bank_details",
          headers: { 'Authorization' => "Bearer #{access_token_for(finance)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'account_number')).to eq('PK24SCBL0000001123456702')
      expect(AuditEvent.order(:id).last.action_code).to eq('candidate_bank_detail_viewed_unmasked')
    end

    it 'rejects unauthorized roles, candidate tokens, and unknown current records safely' do
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)
      hr_user = create(:user, role: 'hr')

      get "/api/v1/admin/candidates/#{candidate.public_id}/bank_details",
          headers: { 'Authorization' => "Bearer #{access_token_for(hr_user)}" }
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/admin/candidates/#{candidate.public_id}/bank_details",
          headers: { 'Authorization' => "Bearer #{candidate_token_for(candidate)}" }
      expect(response).to have_http_status(:unauthorized)

      finance = create(:user, role: 'finance')
      get "/api/v1/admin/candidates/#{candidate.public_id}/bank_details",
          headers: { 'Authorization' => "Bearer #{access_token_for(finance)}" }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('candidate_bank_detail_not_found')
    end
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/bank_details/proof_access' do
    it 'returns a short-lived private proof URL for authorized staff and the proxied file is non-cacheable' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      create(:candidate_bank_detail, candidate_assignment: assignment)
      finance = create(:user, role: 'finance')

      post "/api/v1/admin/candidates/#{candidate.public_id}/bank_details/proof_access",
           headers: { 'Authorization' => "Bearer #{access_token_for(finance)}" }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('private')
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.parsed_body.dig('data', 'url')).to include('/rails/active_storage/blobs/proxy/')
      expect(AuditEvent.order(:id).last.action_code).to eq('candidate_bank_proof_accessed')

      get response.parsed_body.dig('data', 'url')

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('private')
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'rejects unauthorized proof access and missing attachments with localized safe errors' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      bank_detail = create(:candidate_bank_detail, candidate_assignment: assignment)
      management = create(:user, role: 'management')

      post "/api/v1/admin/candidates/#{candidate.public_id}/bank_details/proof_access",
           headers: { 'Authorization' => "Bearer #{access_token_for(management)}", 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('bank_detail_proof_access_forbidden')
      expect(response.headers['Content-Language']).to eq('ur')

      finance = create(:user, role: 'finance')
      bank_detail.proof.purge

      post "/api/v1/admin/candidates/#{candidate.public_id}/bank_details/proof_access",
           headers: { 'Authorization' => "Bearer #{access_token_for(finance)}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('bank_proof_attachment_missing')
    end
  end
end

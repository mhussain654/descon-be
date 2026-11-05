# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Bank Detail Reviews', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let!(:bank_detail) { create(:candidate_bank_detail, candidate_assignment: assignment) }
  let(:base_path) { "/api/v1/admin/candidates/#{candidate.public_id}/bank_details" }

  def headers_for(user, idempotency_key: SecureRandom.uuid)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}",
      'Content-Type' => 'application/json', 'Idempotency-Key' => idempotency_key }.compact
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/bank_details/verification' do
    it 'verifies the bank details for staff who manage payments' do
      finance = create(:user, role: 'finance')

      post "#{base_path}/verification", headers: headers_for(finance)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch('data')).to include(
        'status' => 'verified', 'rejection_reason' => nil, 'reviewed_by' => { 'id' => finance.public_id,
                                                                              'role' => 'finance' }
      )
    end

    it 'forbids staff who cannot see full bank details' do
      post "#{base_path}/verification", headers: headers_for(create(:user, role: 'hr'))

      expect(response).to have_http_status(:forbidden)
      expect(bank_detail.reload.status_code).to eq('submitted')
    end

    it 'requires an Idempotency-Key header' do
      post "#{base_path}/verification", headers: headers_for(create(:user, role: 'admin'), idempotency_key: nil)

      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_idempotency_key')
    end
  end

  describe 'POST /api/v1/admin/candidates/:candidate_id/bank_details/rejection' do
    it 'rejects with the reason' do
      post "#{base_path}/rejection", params: { rejection: { reason: 'The IBAN does not match the cheque.' } }.to_json,
                                     headers: headers_for(create(:user, role: 'admin'))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch('data'))
        .to include('status' => 'rejected', 'rejection_reason' => 'The IBAN does not match the cheque.')
    end

    it 'names the reason field when it is missing' do
      post "#{base_path}/rejection", params: { rejection: { reason: '' } }.to_json,
                                     headers: headers_for(create(:user, role: 'admin'))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('rejection.reason')
    end
  end
end

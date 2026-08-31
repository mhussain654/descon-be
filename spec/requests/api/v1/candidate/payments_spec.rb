# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Payments', type: :request do
  before do
    ensure_canonical_workflow_stages!
  end

  def candidate_access_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  def candidate_auth_headers(candidate, extra_headers = {})
    { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }.merge(extra_headers)
  end

  describe 'GET /api/v1/candidate/payment' do
    it 'returns blocking information before the fee stage and exposes no-store freshness headers' do
      candidate = create(:candidate, status_code: 'documents_uploaded')
      create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: WorkflowStage.find_by!(code: 'documents_uploaded')
      )

      get '/api/v1/candidate/payment', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.headers['ETag']).to be_present
      expect(response.parsed_body.dig('data', 'eligible')).to be(false)
      expect(response.parsed_body.dig('data', 'blocking_reasons')).to eq(['payment_stage_not_reached'])
    end
  end

  describe 'POST /api/v1/candidate/payment' do
    it 'creates an idempotent hosted checkout attempt and advances verified candidates to fee_pending' do
      candidate = create(:candidate, status_code: 'verified')
      assignment = create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: WorkflowStage.find_by!(code: 'verified')
      )
      create_all_verified_required_documents(assignment:)
      headers = candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-payment-1')

      post '/api/v1/candidate/payment', headers: headers

      expect(response).to have_http_status(:created)
      first_payment_id = response.parsed_body.dig('data', 'payment', 'id')
      expect(response.parsed_body.dig('data', 'payment', 'status')).to eq('checkout_pending')
      expect(response.parsed_body.dig('data', 'payment', 'provider')).to eq('mock_hosted_checkout')
      expect(response.parsed_body.dig('data', 'payment', 'checkout_url')).to be_present
      expect(candidate.reload.status_code).to eq('fee_pending')
      expect(assignment.reload.current_workflow_stage.code).to eq('fee_pending')
      expect(Payment.count).to eq(1)

      post '/api/v1/candidate/payment', headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'payment', 'id')).to eq(first_payment_id)
      expect(Payment.count).to eq(1)
      expect(AuditEvent.where(action_code: 'candidate_payment_checkout_initiated').count).to eq(1)
    end

    it 'rejects checkout initiation when payment eligibility prerequisites are not met' do
      candidate = create(:candidate, status_code: 'verified')
      create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: WorkflowStage.find_by!(code: 'verified')
      )

      post '/api/v1/candidate/payment',
           headers: candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-payment-2')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('payment_not_eligible')
      expect(response.parsed_body.dig('errors', 0, 'details', 'blocking_reasons'))
        .to eq(['required_documents_not_verified'])
      expect(Payment.count).to eq(0)
    end

    it 'fails safely when the configured provider is unavailable' do
      candidate = create(:candidate, status_code: 'verified')
      assignment = create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: WorkflowStage.find_by!(code: 'verified')
      )
      create_all_verified_required_documents(assignment:)
      headers = candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-payment-3')

      allow(Payments::ProviderRegistry).to receive(:fetch).and_raise(Payments::ProviderNotConfiguredError)

      post '/api/v1/candidate/payment', headers: headers

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('payment_checkout_unavailable')
      expect(Payment.count).to eq(0)
      expect(candidate.reload.status_code).to eq('verified')
    end
  end
end

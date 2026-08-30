# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Bank Details', type: :request do
  def candidate_access_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  def candidate_auth_headers(candidate, extra_headers = {})
    { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }.merge(extra_headers)
  end

  describe 'GET /api/v1/candidate/bank_details' do
    it 'returns a missing state when the authenticated candidate has no current bank detail' do
      candidate = create(:candidate)

      get '/api/v1/candidate/bank_details', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'status')).to eq('missing')
      expect(response.parsed_body.dig('data', 'bank_detail')).to be_nil
    end

    it 'returns the authenticated candidate bank detail with a masked account number only' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      bank_detail = create(
        :candidate_bank_detail,
        candidate_assignment: assignment,
        account_number: 'PK24SCBL0000001123456702'
      )

      get '/api/v1/candidate/bank_details', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'status')).to eq('submitted')
      expect(response.parsed_body.dig('data', 'bank_detail', 'id')).to eq(bank_detail.public_id)
      expect(response.parsed_body.dig('data', 'bank_detail', 'account_number')).to end_with('6702')
      expect(response.parsed_body.dig('data', 'bank_detail', 'account_number')).not_to eq(bank_detail.account_number)
      expect(response.body).not_to include('/storage/')
    end

    it 'rejects inactive candidates and staff tokens' do
      inactive_candidate = create(:candidate, active: false)

      get '/api/v1/candidate/bank_details',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(inactive_candidate)}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin', password: 'Password123!')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }

      get '/api/v1/candidate/bank_details',
          headers: { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PUT /api/v1/candidate/bank_details' do
    it 'creates bank details with mandatory proof and supports safe replay after token renewal' do
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)
      headers = { 'Idempotency-Key' => 'candidate-bank-detail-1' }

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: 'Ahmed Ali',
              account_number: 'PK24 SCBL 0000001123456702',
              bank_name: 'Meezan Bank',
              proof: fixture_upload('test.pdf', 'application/pdf')
            }
          },
          headers: candidate_auth_headers(candidate, headers)

      expect(response).to have_http_status(:created)
      first_id = response.parsed_body.dig('data', 'bank_detail', 'id')
      expect(response.parsed_body.dig('data', 'bank_detail', 'account_number')).to end_with('6702')
      expect(response.parsed_body.dig('data', 'message')).to eq(I18n.t('api.candidate_bank_details.submitted'))

      expect do
        put '/api/v1/candidate/bank_details',
            params: {
              bank_detail: {
                account_title: 'Ahmed Ali',
                account_number: 'PK24 SCBL 0000001123456702',
                bank_name: 'Meezan Bank',
                proof: fixture_upload('test.pdf', 'application/pdf')
              }
            },
            headers: candidate_auth_headers(candidate, headers)
      end.not_to change(CandidateBankDetail, :count)

      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(response.parsed_body.dig('data', 'bank_detail', 'id')).to eq(first_id)
    end

    it 'rejects missing proof, invalid account numbers, and same-key reuse with different payload' do
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)
      headers = candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-bank-detail-2', 'X-Locale' => 'ur')

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: 'Ahmed Ali',
              account_number: 'PK24SCBL0000001123456702',
              bank_name: 'Meezan Bank'
            }
          },
          headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_proof')
      expect(response.headers['Content-Language']).to eq('ur')

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: 'Ahmed Ali',
              account_number: 'bad-123',
              bank_name: 'Meezan Bank',
              proof: fixture_upload('test.pdf', 'application/pdf')
            }
          },
          headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_account_number')

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: 'Ahmed Ali',
              account_number: 'PK24SCBL0000001123456702',
              bank_name: 'Meezan Bank',
              proof: fixture_upload('test.pdf', 'application/pdf')
            }
          },
          headers: candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-bank-detail-3')

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: 'Ahmed Ali',
              account_number: 'PK24SCBL0000001123456703',
              bank_name: 'Meezan Bank',
              proof: fixture_upload('test.pdf', 'application/pdf')
            }
          },
          headers: candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-bank-detail-3')

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('idempotency_conflict')
    end

    it 'returns field-addressable validation errors for missing banking attributes' do
      candidate = create(:candidate)
      create(:candidate_assignment, candidate:)

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: '',
              account_number: 'PK24SCBL0000001123456702',
              bank_name: 'Meezan Bank',
              proof: fixture_upload('test.pdf', 'application/pdf')
            }
          },
          headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_account_title')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('bank_detail.account_title')

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: 'Ahmed Ali',
              account_number: '',
              bank_name: 'Meezan Bank',
              proof: fixture_upload('test.pdf', 'application/pdf')
            }
          },
          headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_account_number')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('bank_detail.account_number')

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: 'Ahmed Ali',
              account_number: 'PK24SCBL0000001123456702',
              bank_name: '',
              proof: fixture_upload('test.pdf', 'application/pdf')
            }
          },
          headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_bank_name')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('bank_detail.bank_name')
    end

    it 'preserves the previous record when replacement persistence fails' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:)
      original_record = create(:candidate_bank_detail, candidate_assignment: assignment, account_number: 'PK24SCBL0001')

      allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(build(:audit_event)))

      put '/api/v1/candidate/bank_details',
          params: {
            bank_detail: {
              account_title: 'Updated Name',
              account_number: 'PK24SCBL0002',
              bank_name: 'Updated Bank',
              proof: fixture_upload('test.pdf', 'application/pdf')
            }
          },
          headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(original_record.reload).to be_current_version
      expect(original_record.account_number).to eq('PK24SCBL0001')
      expect(assignment.candidate_bank_details.current_version.count).to eq(1)
    end
  end
end

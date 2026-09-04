# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Payments', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  def login_as(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{login_as(user)}" }
  end

  def payment_for(full_name: 'Ahmed Ali', reference_number: "DES-#{SecureRandom.hex(4).upcase}", **attrs)
    candidate = create(:candidate, full_name:,
                                   cnic: "42101-#{format('%07d', SecureRandom.random_number(10_000_000))}-1")
    assignment = create(:candidate_assignment, candidate:, reference_number:,
                                               current_workflow_stage: WorkflowStage.find_by!(code: 'fee_paid'))
    create(:payment, candidate_assignment: assignment, external_reference: "EXT-#{SecureRandom.hex(4).upcase}", **attrs)
  end

  describe 'GET /api/v1/admin/payments' do
    it 'allows a finance staff member (manage_payments) to list payments with masked candidate identity' do
      finance = create(:user, role: 'finance')
      payment = payment_for(full_name: 'Zainab Bibi')

      get '/api/v1/admin/payments', headers: auth_headers(finance)

      expect(response).to have_http_status(:ok)
      row = response.parsed_body.dig('data', 0)
      expect(row['id']).to eq(payment.public_id)
      expect(row['candidate']['full_name']).to eq('Zainab Bibi')
      expect(row['candidate']['masked_cnic']).to match(/\A\d{5}-\*{7}-\d\z/)
      expect(row['candidate']).not_to have_key('cnic')
      expect(row['reconciliation_state']).to eq('clean')
    end

    it 'allows a management staff member (view_payments) to list payments too' do
      management = create(:user, role: 'management')
      payment_for

      get '/api/v1/admin/payments', headers: auth_headers(management)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].size).to eq(1)
    end

    it 'forbids a staff member with neither view_payments nor manage_payments' do
      hr = create(:user, role: 'hr')

      get '/api/v1/admin/payments', headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('forbidden')
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/payments'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'filters by status and reports applied_filters' do
      finance = create(:user, role: 'finance')
      paid = payment_for(status_code: 'paid', paid_at: Time.current)
      payment_for(status_code: 'checkout_pending', external_reference: nil)

      get '/api/v1/admin/payments', params: { filter: { status: 'paid' } }, headers: auth_headers(finance)

      expect(response.parsed_body['data'].pluck('id')).to eq([paid.public_id])
      expect(response.parsed_body.dig('meta', 'applied_filters')).to eq('status' => 'paid')
    end

    it 'searches by candidate name' do
      finance = create(:user, role: 'finance')
      match = payment_for(full_name: 'Distinctive Name')
      payment_for(full_name: 'Someone Else')

      get '/api/v1/admin/payments', params: { search: 'Distinctive' }, headers: auth_headers(finance)

      expect(response.parsed_body['data'].pluck('id')).to eq([match.public_id])
    end

    it 'rejects an unsupported filter with a validation error' do
      finance = create(:user, role: 'finance')

      get '/api/v1/admin/payments', params: { filter: { bogus: 'x' } }, headers: auth_headers(finance)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.bogus')
    end

    it 'paginates results' do
      finance = create(:user, role: 'finance')
      3.times { payment_for }

      get '/api/v1/admin/payments', params: { page: { number: 1, size: 2 } }, headers: auth_headers(finance)

      expect(response.parsed_body['data'].size).to eq(2)
      expect(response.parsed_body.dig('meta', 'pagination')).to include('total_count' => 3, 'total_pages' => 2)
    end
  end

  describe 'GET /api/v1/admin/payments/:id' do
    it "returns the payment's full detail including safe events and reconciliation findings" do
      finance = create(:user, role: 'finance')
      payment = payment_for
      create(:payment_event, payment:, event_type: 'payment_succeeded',
                             payload: { 'secret_signature' => 'do-not-leak' })
      run = create(:payment_reconciliation_run)
      create(:payment_reconciliation_finding, payment_reconciliation_run: run, payment:,
                                              finding_code: 'paid_at_missing')

      get "/api/v1/admin/payments/#{payment.public_id}", headers: auth_headers(finance)

      expect(response).to have_http_status(:ok)
      expect(response.headers['ETag']).to be_present
      body = response.parsed_body['data']
      expect(body['id']).to eq(payment.public_id)
      expect(body['payment_events'].size).to eq(1)
      expect(body['payment_events'].first).not_to have_key('payload')
      expect(body['payment_events'].first).not_to have_key('secret_signature')
      expect(body['reconciliation_findings'].first['finding_code']).to eq('paid_at_missing')
      expect(body['reconciliation_findings'].first['state']).to eq('open')
    end

    it 'returns not_found for an unknown payment id' do
      finance = create(:user, role: 'finance')

      get '/api/v1/admin/payments/does-not-exist', headers: auth_headers(finance)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('payment_not_found')
    end

    it 'forbids a staff member without view_payments/manage_payments' do
      hr = create(:user, role: 'hr')
      payment = payment_for

      get "/api/v1/admin/payments/#{payment.public_id}", headers: auth_headers(hr)

      expect(response).to have_http_status(:forbidden)
    end
  end
end

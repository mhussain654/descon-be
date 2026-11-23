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

    it "narrows to one import batch's payments by the candidate's registered date and country" do
      finance = create(:user, role: 'finance')
      batch = payment_for(full_name: 'Batch Payer')
      batch.candidate_assignment.candidate.update!(created_at: Time.utc(2026, 11, 20, 6, 0))
      later = payment_for(full_name: 'Later Batch')
      later.candidate_assignment.candidate.update!(created_at: Time.utc(2026, 11, 28, 6, 0))

      get '/api/v1/admin/payments',
          params: { filter: { registered_from: '2026-11-20', registered_to: '2026-11-21',
                              country_code: batch.candidate_assignment.country.code } },
          headers: auth_headers(finance)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].pluck('id')).to eq([batch.public_id])

      get '/api/v1/admin/payments', params: { filter: { country_code: 'atlantis' } }, headers: auth_headers(finance)
      expect(response).to have_http_status(:bad_request)
    end

    it 'includes a zero-filled payment-status summary in meta' do
      finance = create(:user, role: 'finance')
      payment_for(status_code: 'paid')
      payment_for(status_code: 'failed')

      get '/api/v1/admin/payments', headers: auth_headers(finance)

      expect(response.parsed_body.dig('meta', 'summary')).to eq(
        [
          { 'code' => 'checkout_pending', 'count' => 0 },
          { 'code' => 'paid', 'count' => 1 },
          { 'code' => 'failed', 'count' => 1 },
          { 'code' => 'cancelled', 'count' => 0 }
        ]
      )
    end

    it 'filters by the day the fee was paid (Pakistan time) and totals the paid fees under the filters' do
      finance = create(:user, role: 'finance')
      travel_to Time.utc(2026, 11, 23, 7, 0) do # 12:00 on 23 Nov in Pakistan
        early = payment_for(full_name: 'Paid After Midnight', paid_at: Time.utc(2026, 11, 22, 19, 30)) # 00:30 PKT
        noon = payment_for(full_name: 'Paid At Noon', amount: 26_800, paid_at: Time.utc(2026, 11, 23, 7, 0))
        payment_for(full_name: 'Paid Yesterday', paid_at: Time.utc(2026, 11, 22, 18, 30)) # 23:30 PKT on 22 Nov
        payment_for(full_name: 'Still Pending', status_code: 'checkout_pending', paid_at: nil)

        get '/api/v1/admin/payments', params: { filter: { paid_from: '2026-11-23', paid_to: '2026-11-23' } },
                                      headers: auth_headers(finance)

        expect(response.parsed_body['data'].pluck('id')).to contain_exactly(early.public_id, noon.public_id)
        expect(response.parsed_body.dig('meta', 'paid_total')).to eq(
          'candidate_count' => 2, 'payment_count' => 2,
          'amounts' => [{ 'currency_code' => 'PKR', 'amount' => '28300.00' }]
        )
      end
    end

    it 'totals every paid fee when no paid date is chosen, and none when nothing matches' do
      finance = create(:user, role: 'finance')
      payment_for(status_code: 'paid')
      payment_for(status_code: 'failed', paid_at: nil)

      get '/api/v1/admin/payments', headers: auth_headers(finance)
      expect(response.parsed_body.dig('meta', 'paid_total'))
        .to eq('candidate_count' => 1, 'payment_count' => 1,
               'amounts' => [{ 'currency_code' => 'PKR', 'amount' => '1500.00' }])

      get '/api/v1/admin/payments', params: { search: 'nobody-matches' }, headers: auth_headers(finance)
      expect(response.parsed_body.dig('meta', 'paid_total'))
        .to eq('candidate_count' => 0, 'payment_count' => 0, 'amounts' => [])
    end

    it 'rejects a malformed or reversed paid date range' do
      finance = create(:user, role: 'finance')
      headers = auth_headers(finance)

      get '/api/v1/admin/payments', params: { filter: { paid_from: '23/11/2026' } }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.paid_from')

      get '/api/v1/admin/payments', params: { filter: { paid_from: '2026-11-23', paid_to: '2026-11-22' } },
                                    headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.paid_to')
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
      expect(body).not_to have_key('voucher_number')
    end

    it 'includes the voucher number of a voucher payment' do
      finance = create(:user, role: 'finance')
      payment = payment_for(provider_code: 'kuickpay_voucher', voucher_number: '10420261000061939')

      get "/api/v1/admin/payments/#{payment.public_id}", headers: auth_headers(finance)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']['voucher_number']).to eq('10420261000061939')
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

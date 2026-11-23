# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Manual Payments', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
    create_all_verified_required_documents(assignment:)
  end

  let(:candidate) { create(:candidate, status_code: 'fee_pending') }
  let(:assignment) do
    create(:candidate_assignment, candidate:, current_workflow_stage: WorkflowStage.find_by!(code: 'fee_pending'),
                                  onboarding_fee_amount: '1500')
  end
  let(:path) { "/api/v1/admin/candidates/#{candidate.public_id}/manual_payment" }
  let(:developer) { create(:user, role: 'developer') }
  let(:valid_params) { { manual_payment: { reference: '788895', paid_on: '2026-11-23', reason: 'Paid at KuickPay' } } }

  def headers_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def open_voucher
    create(:payment, candidate_assignment: assignment, amount: BigDecimal('1500'), provider_code: 'kuickpay_voucher',
                     status_code: 'checkout_pending', voucher_number: '0000811111', provider_order_id: 'PAY-1',
                     checkout_expires_at: 5.days.from_now, paid_at: nil)
  end

  around { |example| travel_to(Time.utc(2026, 11, 23, 7, 0)) { example.run } } # 12:00 on 23 Nov in Pakistan

  it "marks the candidate's open voucher paid and moves them to Fee Paid", :aggregate_failures do
    voucher = open_voucher
    headers = headers_for(developer)

    post path, params: valid_params, headers: headers

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['data']).to include('id' => voucher.public_id, 'status' => 'paid',
                                                    'external_reference' => '788895', 'provider' => 'kuickpay_voucher')
    expect(voucher.reload).to have_attributes(status_code: 'paid', recorded_by: developer, note: 'Paid at KuickPay',
                                              paid_at: Time.current)
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
    event = PaymentEvent.find_by!(event_type: 'payment_marked_paid')
    expect(event).to have_attributes(actor: developer, event_source: 'staff_manual', provider_transaction_id: '788895')
    audit = AuditEvent.find_by!(action_code: 'candidate_payment_marked_paid')
    expect(audit).to have_attributes(actor: developer, entity_id: voucher.id)
    expect(audit.metadata).to include('reference' => '788895', 'paid_on' => '2026-11-23')
  end

  it 'records a manual payment for the current fee when the candidate has no open payment' do
    headers = headers_for(developer)

    post path, params: { manual_payment: { reference: 'KP-1', paid_on: '2026-11-20', reason: 'Bank deposit' } },
               headers: headers

    expect(response).to have_http_status(:created)
    payment = assignment.payments.sole
    expect(payment).to have_attributes(status_code: 'paid', provider_code: 'manual', amount: BigDecimal('1500'),
                                       payment_type_code: 'onboarding_fee', external_reference: 'KP-1')
    expect(payment.paid_at).to eq(Time.find_zone!('Asia/Karachi').local(2026, 11, 20, 12))
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
  end

  it 'refuses a candidate who is not at Fee Pending, or who has already paid' do
    headers = headers_for(developer)
    create(:payment, candidate_assignment: assignment, status_code: 'paid', external_reference: 'OLD-1')

    post path, params: valid_params, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('manual_payment_not_allowed')

    Payment.delete_all
    assignment.update!(current_workflow_stage: WorkflowStage.find_by!(code: 'fee_paid'))
    post path, params: valid_params, headers: headers
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('manual_payment_not_allowed')
    expect(Payment.count).to eq(0)
  end

  it 'rejects a missing reference or reason, a future or malformed day, and a reference already used' do
    headers = headers_for(developer)
    create(:payment, candidate_assignment: create(:candidate_assignment), external_reference: '788895')

    { { reference: ' ' } => 'manual_payment.reference', { reason: '' } => 'manual_payment.reason',
      { reason: 'x' * 501 } => 'manual_payment.reason', { reference: 'x' * 101 } => 'manual_payment.reference',
      { paid_on: '2026-11-24' } => 'manual_payment.paid_on', { paid_on: '23/11/2026' } => 'manual_payment.paid_on',
      {} => 'manual_payment.reference' }.each do |change, field|
      post path, params: { manual_payment: valid_params[:manual_payment].merge(change) }, headers: headers
      expect(response).to have_http_status(:unprocessable_content), change.inspect
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq(field), change.inspect
    end
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_pending')
    expect(assignment.payments.count).to eq(0)
  end

  it 'is for developers only' do
    open_voucher
    %w[admin finance].each do |role|
      post path, params: valid_params, headers: headers_for(create(:user, role:))
      expect(response).to have_http_status(:forbidden), role
    end
    expect(Payment.where(status_code: 'paid')).to be_empty
  end

  it 'returns not found for an unknown candidate' do
    post '/api/v1/admin/candidates/00000000-0000-0000-0000-000000000000/manual_payment', params: valid_params,
                                                                                         headers: headers_for(developer)
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects an unauthenticated request' do
    post path, params: valid_params
    expect(response).to have_http_status(:unauthorized)
  end
end

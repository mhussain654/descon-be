# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Hosted Checkout Notifications', type: :request do
  before do
    ensure_canonical_workflow_stages!
  end

  def mock_provider
    Payments::Providers::MockHostedCheckoutAdapter.new(configuration: Payments::Configuration.new)
  end

  def payment_notification_payload(payment:, status:, transaction_id:, response_code: '00', currency: 'PKR')
    payload = {
      'orderid' => payment.provider_order_id,
      'transactionid' => transaction_id,
      'amount' => payment.amount.to_s,
      'currency' => currency,
      'status' => status,
      'responsecode' => response_code
    }

    payload.merge('signature' => mock_provider.sign_notification(payload))
  end

  it 'marks a payment paid exactly once and advances fee_pending to fee_paid for duplicate callbacks and returns' do
    candidate = create(:candidate, status_code: 'fee_pending')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_pending'))
    create_all_verified_required_documents(assignment:)
    payment = create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'checkout_pending',
      paid_at: nil,
      external_reference: nil,
      checkout_url: 'https://mock-payments.example.test/checkout?orderid=1',
      checkout_expires_at: 30.minutes.from_now
    )
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-SUCCESS-1')

    post '/api/v1/payments/hosted_checkout/mock_hosted_checkout/callback', params: payload

    expect(response).to have_http_status(:ok)
    expect(payment.reload.status_code).to eq('paid')
    expect(payment.external_reference).to eq('TXN-SUCCESS-1')
    expect(payment.paid_at).to be_present
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
    expect(candidate.reload.status_code).to eq('fee_paid')
    expect(PaymentEvent.count).to eq(1)
    expect(AuditEvent.where(action_code: 'candidate_payment_paid').count).to eq(1)
    fee_paid_transitions = CandidateStageHistory.where(
      candidate_assignment: assignment,
      to_workflow_stage: stage_for('fee_paid')
    )
    expect(fee_paid_transitions.count).to eq(1)

    get '/api/v1/payments/hosted_checkout/mock_hosted_checkout/return', params: payload

    expect(response).to have_http_status(:ok)
    expect(PaymentEvent.count).to eq(1)
    expect(AuditEvent.where(action_code: 'candidate_payment_paid').count).to eq(1)
    expect(fee_paid_transitions.count).to eq(1)
  end

  it 'ignores out-of-order failure after a successful payment without downgrading workflow state' do
    candidate = create(:candidate, status_code: 'fee_pending')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_pending'))
    create_all_verified_required_documents(assignment:)
    payment = create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'checkout_pending',
      paid_at: nil,
      external_reference: nil
    )

    post '/api/v1/payments/hosted_checkout/mock_hosted_checkout/callback',
         params: payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-SUCCESS-2')
    post '/api/v1/payments/hosted_checkout/mock_hosted_checkout/callback',
         params: payment_notification_payload(
           payment:,
           status: 'FAILED',
           transaction_id: 'TXN-FAILED-2',
           response_code: '05'
         )

    expect(response).to have_http_status(:ok)
    expect(payment.reload.status_code).to eq('paid')
    expect(payment.external_reference).to eq('TXN-SUCCESS-2')
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
  end

  it 'rejects invalid signatures without persisting payment events or workflow changes' do
    candidate = create(:candidate, status_code: 'fee_pending')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_pending'))
    create_all_verified_required_documents(assignment:)
    payment = create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'checkout_pending',
      paid_at: nil,
      external_reference: nil
    )

    post '/api/v1/payments/hosted_checkout/mock_hosted_checkout/callback',
         params: payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-BAD').merge(
           'signature' => 'bad'
         )

    expect(response).to have_http_status(:unauthorized)
    expect(payment.reload.status_code).to eq('checkout_pending')
    expect(PaymentEvent.count).to eq(0)
    expect(AuditEvent.where(action_code: 'candidate_payment_paid')).to be_empty
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_pending')
  end

  it 'rejects a signed amount mismatch without persisting payment events or workflow changes' do
    candidate = create(:candidate, status_code: 'fee_pending')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_pending'))
    create_all_verified_required_documents(assignment:)
    payment = create(:payment, candidate_assignment: assignment, status_code: 'checkout_pending')
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-AMOUNT-1')
    payload['amount'] = '9999.00'
    payload['signature'] = mock_provider.sign_notification(payload.except('signature'))

    post '/api/v1/payments/hosted_checkout/mock_hosted_checkout/callback', params: payload

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('payment_notification_mismatch')
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('payment_notification.amount')
    expect(payment.reload.status_code).to eq('checkout_pending')
    expect(PaymentEvent.count).to eq(0)
  end

  it 'rejects a signed currency mismatch without persisting payment events or workflow changes' do
    candidate = create(:candidate, status_code: 'fee_pending')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_pending'))
    create_all_verified_required_documents(assignment:)
    payment = create(:payment, candidate_assignment: assignment, status_code: 'checkout_pending')
    payload = payment_notification_payload(
      payment:,
      status: 'SUCCESS',
      transaction_id: 'TXN-CURRENCY-1',
      currency: 'USD'
    )

    post '/api/v1/payments/hosted_checkout/mock_hosted_checkout/callback', params: payload

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('payment_notification_mismatch')
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('payment_notification.currency')
    expect(payment.reload.status_code).to eq('checkout_pending')
    expect(PaymentEvent.count).to eq(0)
  end

  it 'rejects conflicting signed success after a payment is already finalized' do
    candidate = create(:candidate, status_code: 'fee_paid')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_paid'))
    payment = create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      external_reference: 'TXN-PAID-1',
      provider_transaction_id: 'TXN-PAID-1',
      provider_status_code: 'SUCCESS',
      paid_at: Time.current
    )
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-OTHER-1')

    post '/api/v1/payments/hosted_checkout/mock_hosted_checkout/callback', params: payload

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('payment_notification_conflict')
    expect(PaymentEvent.count).to eq(0)
    expect(payment.reload.external_reference).to eq('TXN-PAID-1')
    expect(AuditEvent.where(action_code: 'candidate_payment_failed').count).to eq(1)
  end
end

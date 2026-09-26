# frozen_string_literal: true

require 'rails_helper'

# HostedCheckoutReturnsController is the browser-facing route KuickPay redirects the
# candidate to after payment -- an unauthenticated response reachable by anyone who
# lands on the URL. Every outcome here must redirect to the frontend's pending page
# and never render payment/workflow data or internal error detail as JSON (that's
# `hosted_checkout_notifications_spec.rb`'s job for the server-to-server /callback
# route, which is unaffected by this behavior).
RSpec.describe 'API V1 Hosted Checkout Returns', type: :request do
  around do |example|
    original_env = ENV.to_h
    ENV['FRONTEND_PAYMENT_RETURN_URL'] = frontend_url
    example.run
  ensure
    ENV.replace(original_env)
  end

  before do
    ensure_canonical_workflow_stages!
  end

  def frontend_url
    'https://app.example.test/payment/pending'
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

  def create_pending_payment
    candidate = create(:candidate, status_code: 'fee_pending')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_pending'))
    create_all_verified_required_documents(assignment:)
    create(:payment, candidate_assignment: assignment, status_code: 'checkout_pending', paid_at: nil,
                     external_reference: nil)
  end

  it 'redirects a successful GET return to the frontend pending page with no body and no query params' do
    payment = create_pending_payment
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-RETURN-OK')

    get '/api/v1/payments/hosted_checkout/mock_hosted_checkout/return', params: payload

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('paid')
  end

  it 'redirects a successful POST return with :see_other so the browser does not re-submit the payload' do
    payment = create_pending_payment
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-RETURN-POST')

    post '/api/v1/payments/hosted_checkout/mock_hosted_checkout/return', params: payload

    expect(response).to have_http_status(:see_other)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('paid')
  end

  it 'redirects an invalid signature instead of rendering the usual 401 JSON error' do
    payment = create_pending_payment
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-BAD-SIG')
              .merge('signature' => 'not-a-real-signature')

    get '/api/v1/payments/hosted_checkout/mock_hosted_checkout/return', params: payload

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('checkout_pending')
    expect(PaymentEvent.count).to eq(0)
  end

  it 'redirects an amount mismatch instead of rendering the usual 422 JSON error' do
    payment = create_pending_payment
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-MISMATCH')
    payload['amount'] = '9999.00'
    payload['signature'] = mock_provider.sign_notification(payload.except('signature'))

    get '/api/v1/payments/hosted_checkout/mock_hosted_checkout/return', params: payload

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('checkout_pending')
    expect(PaymentEvent.count).to eq(0)
  end

  it 'redirects a conflicting success against an already-paid payment, not the usual 409 JSON error' do
    candidate = create(:candidate, status_code: 'fee_paid')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_paid'))
    payment = create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      external_reference: 'TXN-ALREADY-PAID',
      provider_transaction_id: 'TXN-ALREADY-PAID',
      provider_status_code: 'SUCCESS',
      paid_at: Time.current
    )
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-CONFLICTING')

    get '/api/v1/payments/hosted_checkout/mock_hosted_checkout/return', params: payload

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.external_reference).to eq('TXN-ALREADY-PAID')
  end

  it 'redirects for an unknown provider_code instead of rendering the usual JSON error' do
    payment = create_pending_payment
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-UNKNOWN-PROVIDER')

    get '/api/v1/payments/hosted_checkout/not_a_real_provider/return', params: payload

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
  end

  it 'falls back to an empty response instead of crashing when FRONTEND_PAYMENT_RETURN_URL is not configured' do
    ENV.delete('FRONTEND_PAYMENT_RETURN_URL')
    payment = create_pending_payment
    payload = payment_notification_payload(payment:, status: 'SUCCESS', transaction_id: 'TXN-NO-FRONTEND-URL')

    get '/api/v1/payments/hosted_checkout/mock_hosted_checkout/return', params: payload

    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('paid')
  end
end

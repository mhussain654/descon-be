# frozen_string_literal: true

require 'rails_helper'

# HostedCheckoutReturnsController is the browser-facing route KuickPay redirects the
# candidate to after payment -- an unauthenticated response reachable by anyone who
# lands on the URL. Every outcome here must redirect to the frontend's pending page
# and never render payment/workflow data or internal error detail as JSON (that's
# `hosted_checkout_notifications_spec.rb`'s job for the server-to-server /callback
# route, which is unaffected by this behavior).
#
# Per KuickPay's guide, the return redirect itself carries only `status`/`orderid`/
# `sessionid` -- unsigned, "do not treat this redirect as proof of payment on its
# own." So this controller never trusts those params directly; it uses `orderid`
# only to find which payment to verify, then calls the Status API server-side (see
# Payments::VerifyPaymentStatusService) for the authoritative outcome.
RSpec.describe 'API V1 Hosted Checkout Returns', type: :request do
  around do |example|
    original_env = ENV.to_h
    ENV['FRONTEND_PAYMENT_RETURN_URL'] = frontend_url
    with_kuickpay_configured { example.run }
  ensure
    ENV.replace(original_env)
  end

  before do
    ensure_canonical_workflow_stages!
  end

  def frontend_url
    'https://app.example.test/payment/pending'
  end

  # A Payment that has already been through checkout-session creation --
  # carrying the persisted snapshot #verify_status needs to call the Status API.
  def session_snapshot_attributes
    {
      provider_order_id: "PAY-#{SecureRandom.hex(6).upcase}",
      provider_session_id: "session-#{SecureRandom.hex(6)}",
      provider_amount_payable: '1500.00',
      provider_request_timestamp: '2026-08-31T09:00:00Z',
      provider_request_signature: 'persisted-signature=='
    }
  end

  def create_pending_payment
    candidate = create(:candidate, status_code: 'fee_pending')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_pending'))
    create_all_verified_required_documents(assignment:)
    create(:payment, candidate_assignment: assignment, status_code: 'checkout_pending', paid_at: nil,
                     external_reference: nil, **session_snapshot_attributes)
  end

  it 'looks up the payment by orderid, verifies status server-side, and redirects a successful GET return' do
    payment = create_pending_payment
    stub_kuickpay_verify_status(payment_id: 'TXN-RETURN-OK')

    get '/api/v1/payments/hosted_checkout/kuickpay/return',
        params: { orderid: payment.provider_order_id, status: 'SUCCESS' }

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('paid')
    expect(payment.provider_transaction_id).to eq('TXN-RETURN-OK')
  end

  it 'logs exactly what the browser return carried, before any lookup or verification' do
    payment = create_pending_payment
    stub_kuickpay_verify_status(payment_id: 'TXN-RETURN-LOGGED')
    allow(Rails.logger).to receive(:info).and_call_original

    get '/api/v1/payments/hosted_checkout/kuickpay/return',
        params: { orderid: payment.provider_order_id, status: 'SUCCESS', sessionid: 'session-123' }

    expected_log = /\[Payments\]\[kuickpay\]\[return\] method=GET params=.*#{payment.provider_order_id}.*session-123/
    expect(Rails.logger).to have_received(:info).with(a_string_matching(expected_log))
  end

  it 'redirects a successful POST return with :see_other so the browser does not re-submit the payload' do
    payment = create_pending_payment
    stub_kuickpay_verify_status(payment_id: 'TXN-RETURN-POST')

    post '/api/v1/payments/hosted_checkout/kuickpay/return',
         params: { orderid: payment.provider_order_id, status: 'SUCCESS' }

    expect(response).to have_http_status(:see_other)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('paid')
  end

  it 'redirects the same way for the real "session not found" response, leaving the payment untouched' do
    payment = create_pending_payment
    stub_kuickpay_verify_status(found: false)

    get '/api/v1/payments/hosted_checkout/kuickpay/return',
        params: { orderid: payment.provider_order_id, status: 'FAILED' }

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(payment.reload.status_code).to eq('checkout_pending')
  end

  it 'redirects without calling the Status API when the return carries no orderid' do
    create_pending_payment

    get '/api/v1/payments/hosted_checkout/kuickpay/return', params: { status: 'SUCCESS' }

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(PaymentEvent.count).to eq(0)
  end

  it 'redirects silently when the orderid does not match any payment' do
    get '/api/v1/payments/hosted_checkout/kuickpay/return', params: { orderid: 'unknown-order-id', status: 'SUCCESS' }

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(PaymentEvent.count).to eq(0)
  end

  it 'redirects for an unknown provider_code without calling the Status API' do
    payment = create_pending_payment

    get '/api/v1/payments/hosted_checkout/not_a_real_provider/return', params: { orderid: payment.provider_order_id }

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('checkout_pending')
  end

  it 'redirects a conflicting success against an already-paid payment, not the usual 409 JSON error' do
    candidate = create(:candidate, status_code: 'fee_paid')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_paid'))
    payment = create(:payment, candidate_assignment: assignment, status_code: 'paid',
                               external_reference: 'TXN-ALREADY-PAID', provider_transaction_id: 'TXN-ALREADY-PAID',
                               provider_status_code: 'SUCCESS', paid_at: Time.current, **session_snapshot_attributes)
    stub_kuickpay_verify_status(payment_id: 'TXN-CONFLICTING')

    get '/api/v1/payments/hosted_checkout/kuickpay/return',
        params: { orderid: payment.provider_order_id, status: 'SUCCESS' }

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.external_reference).to eq('TXN-ALREADY-PAID')
  end

  it 'redirects silently when the Status API call itself fails (transport error), leaving the payment untouched' do
    payment = create_pending_payment
    allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'getaddrinfo failed')

    get '/api/v1/payments/hosted_checkout/kuickpay/return',
        params: { orderid: payment.provider_order_id, status: 'SUCCESS' }

    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to eq(frontend_url)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('checkout_pending')
    expect(PaymentEvent.count).to eq(0)
  end

  it 'falls back to an empty response instead of crashing when FRONTEND_PAYMENT_RETURN_URL is not configured' do
    ENV.delete('FRONTEND_PAYMENT_RETURN_URL')
    payment = create_pending_payment
    stub_kuickpay_verify_status(payment_id: 'TXN-NO-FRONTEND-URL')

    get '/api/v1/payments/hosted_checkout/kuickpay/return',
        params: { orderid: payment.provider_order_id, status: 'SUCCESS' }

    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty
    expect(payment.reload.status_code).to eq('paid')
  end
end

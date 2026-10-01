# frozen_string_literal: true

# Shared helpers for exercising the real Payments::Providers::
# KuickpayHostedCheckoutAdapter from request/service specs without ever
# reaching the real KuickPay sandbox (AGENTS.md: "Do not call live backend
# or provider services from unit/component tests" / "no live calls in the
# automated test suite"). KuickPay is the only payment provider this app
# integrates with -- there is no mock adapter to fall back to instead.
module KuickpayTestHelpers
  KUICKPAY_TEST_ENV = {
    'KUICKPAY_ENABLED' => 'true',
    'KUICKPAY_COMPANY_ID' => 'test-company-id',
    'KUICKPAY_RETURN_URL' => 'https://app.example.test/return'
  }.freeze

  # Sets the ENV KuickPay needs to be "configured" (available?/
  # configured_for_requests? true -- kuickpay_secured_key is already set in
  # every test run, from config/kuickpay.yml's fixed test fake) for the
  # duration of the example.
  def with_kuickpay_configured
    original = ENV.to_h.slice(*KUICKPAY_TEST_ENV.keys)
    ENV.update(KUICKPAY_TEST_ENV)
    yield
  ensure
    KUICKPAY_TEST_ENV.each_key { |key| ENV[key] = original[key] }
  end

  # Stubs Net::HTTP so a real POST {KUICKPAY_BASE_URL}/checkout/api/session
  # call succeeds with the given sessionID/redirectURL, mirroring
  # kuickpay_hosted_checkout_adapter_spec.rb's own stubbing pattern. Uses
  # the real sandbox response shape (confirmed 2026-09-28) -- no top-level
  # `success` boolean, unlike the guide's documented example -- see
  # KuickpayHostedCheckoutAdapter#session_created?.
  def stub_kuickpay_create_session(
    session_id: 'session-1',
    redirect_url: 'https://gateway.kuickpay.com/pay?session=session-1'
  )
    allow(Net::HTTP).to receive(:start) do |*, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(kuickpay_create_session_response(session_id:, redirect_url:))
      block.call(http)
    end
  end

  def kuickpay_create_session_response(session_id:, redirect_url:)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return(
      { responseData: { responseCode: '00', status: 'success', sessionID: session_id,
                        redirectURL: redirect_url } }.to_json
    )
    response
  end

  # Stubs Net::HTTP so a real POST {KUICKPAY_BASE_URL}/checkout/api/status
  # call returns one of the two response shapes confirmed against the real
  # sandbox (2026-10-01) -- see Payments::VerifyPaymentStatusService's own
  # class comment for the full reasoning. `found: true` (the default) is the
  # only shape VerifyPaymentStatusService currently applies as a payment
  # outcome, and only when `payment_status: '00'` -- any other
  # gatewayResponse value is deliberately left unrecognized, since no real
  # failed-payment response has been observed yet to confirm that shape.
  # `found: false` is the real "Session not found" response.
  def stub_kuickpay_verify_status(found: true, payment_status: '00', payment_id: 'TXN-STATUS-1')
    allow(Net::HTTP).to receive(:start) do |*, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(kuickpay_verify_status_response(found:, payment_status:, payment_id:))
      block.call(http)
    end
  end

  def kuickpay_verify_status_response(found:, payment_status:, payment_id:)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    body = found ? kuickpay_session_found_body(payment_status:, payment_id:) : kuickpay_session_not_found_body
    allow(response).to receive(:body).and_return(body.to_json)
    response
  end

  def kuickpay_session_found_body(payment_status:, payment_id:)
    {
      responseCode: '00',
      responseDescription: 'Session found',
      status: true,
      gatewayResponse: { paymentStatus: payment_status, paymentID: payment_id }
    }
  end

  def kuickpay_session_not_found_body
    { responseCode: '01', responseDescription: 'Session not found', status: 'failure' }
  end

  # Builds a payload signed the same way
  # KuickpayHostedCheckoutAdapter#notification_signature verifies it
  # (orderid+transactionid+amount+status+responsecode, no separator, hex
  # HMAC-SHA256) -- using the fixed fake secured_key config/kuickpay.yml
  # gives the test environment, exactly as a real KuickPay callback/return
  # would need to be signed with the real SecuredKey.
  def kuickpay_signed_notification(payment:, status:, transaction_id:, response_code: '00', currency: nil)
    payload = {
      'orderid' => payment.provider_order_id,
      'transactionid' => transaction_id,
      'amount' => payment.amount.to_s,
      'status' => status,
      'responsecode' => response_code
    }
    payload['currency'] = currency if currency
    payload.merge('signature' => kuickpay_notification_signature(payload))
  end

  def kuickpay_notification_signature(payload)
    data = [payload['orderid'], payload['transactionid'].to_s, payload['amount'], payload['status'],
            payload['responsecode']].join
    OpenSSL::HMAC.hexdigest('SHA256', Payments::Configuration.new.kuickpay_secured_key, data)
  end
end

RSpec.configure do |config|
  config.include KuickpayTestHelpers, type: :request
end

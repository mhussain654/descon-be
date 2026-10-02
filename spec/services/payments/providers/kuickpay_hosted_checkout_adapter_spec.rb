# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::KuickpayHostedCheckoutAdapter do
  let(:configuration) do
    instance_double(
      Payments::Configuration,
      kuickpay_enabled?: true,
      kuickpay_company_id: 'merchant-1',
      kuickpay_secured_key: 'secret-1',
      kuickpay_return_url: 'https://app.example.test/return',
      kuickpay_base_url: 'https://sandbox-api.kuickpay.com',
      checkout_expires_in_minutes: 30,
      kuickpay_open_timeout: 5,
      kuickpay_read_timeout: 10
    )
  end

  let(:adapter) { described_class.new(configuration:) }

  it 'reports availability only when required configuration is present' do
    expect(adapter.available?).to be(true)

    missing_return_url = instance_double(
      Payments::Configuration,
      kuickpay_enabled?: true,
      kuickpay_company_id: 'merchant-1',
      kuickpay_secured_key: 'secret-1',
      kuickpay_return_url: nil
    )

    expect(described_class.new(configuration: missing_return_url).available?).to be(false)
  end

  it 'builds a checkout session from a successful response (real sandbox shape), carrying the request snapshot' do
    payment = build_stubbed(:payment, public_id: 'payment-public-id', provider_order_id: 'PAY-ORDER-123')
    captured_request = nil
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    # Confirmed 2026-09-28 against a real sandbox call -- unlike the guide's
    # documented example, there is no top-level `success` boolean; the real
    # indicator is responseData.status/responseCode (see session_created?).
    allow(response).to receive(:body).and_return({
      responseData: {
        responseCode: '00',
        responseDescription: 'Session started successfully',
        status: 'success',
        sessionID: 'session-1',
        redirectURL: 'https://checkout.example.test/session-1'
      }
    }.to_json)

    allow(Net::HTTP).to receive(:start) do |host, _port, **kwargs, &block|
      expect(host).to eq('sandbox-api.kuickpay.com')
      expect(kwargs[:use_ssl]).to be(true)
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { |request| captured_request = request }.and_return(response)
      block.call(http)
    end

    travel_to(Time.zone.parse('2026-08-31T09:00:00Z')) do
      session = adapter.create_checkout_session(payment:, amount: BigDecimal('1500'), currency_code: 'PKR')

      expect(session.provider_code).to eq('kuickpay')
      expect(session.session_id).to eq('session-1')
      expect(session.checkout_url).to eq('https://checkout.example.test/session-1')
      expect(session.expires_at).to eq(Time.zone.parse('2026-08-31T09:30:00Z'))
      expect(session.provider_request_timestamp).to eq('2026-08-31T09:00:00Z')
      expect(session.provider_amount_payable).to eq('1500.00')
      expect(session.provider_request_signature).to be_present
      expect(session.raw_response).to eq(
        'responseData' => {
          'responseCode' => '00',
          'responseDescription' => 'Session started successfully',
          'status' => 'success',
          'sessionID' => 'session-1',
          'redirectURL' => 'https://checkout.example.test/session-1'
        }
      )
    end

    expect(captured_request.path).to eq('/checkout/api/session')
    body = JSON.parse(captured_request.body)
    expect(body).not_to have_key('currency')
  end

  it 'builds a checkout session from the guide-documented top-level success:true shape too' do
    payment = build_stubbed(:payment, provider_order_id: 'PAY-ORDER-123')
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({
      success: true,
      responseData: { sessionID: 'session-2', redirectURL: 'https://checkout.example.test/session-2' }
    }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(response)

    session = adapter.create_checkout_session(payment:, amount: BigDecimal('1500'), currency_code: 'PKR')

    expect(session.session_id).to eq('session-2')
  end

  it 'fails safely when KuickPay returns a non-success response or invalid json' do
    payment = build_stubbed(:payment, provider_order_id: 'PAY-ORDER-123')
    unsuccessful = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(unsuccessful).to receive(:body).and_return({ responseData: { status: 'failed', responseCode: '05' } }.to_json)

    allow(Net::HTTP).to receive(:start).and_return(unsuccessful)
    expect do
      adapter.create_checkout_session(payment:, amount: BigDecimal('1500'), currency_code: 'PKR')
    end.to raise_error(PaymentCheckoutUnavailableError)

    allow(unsuccessful).to receive(:body).and_return('not-json')
    expect do
      adapter.create_checkout_session(payment:, amount: BigDecimal('1500'), currency_code: 'PKR')
    end.to raise_error(PaymentCheckoutUnavailableError)
  end

  describe '#verify_status' do
    let(:payment) do
      build_stubbed(
        :payment,
        provider_order_id: 'PAY-ORDER-123',
        provider_session_id: 'session-123',
        provider_amount_payable: '1500.00',
        provider_request_timestamp: '2026-08-31T09:00:00Z',
        provider_request_signature: 'persisted-signature=='
      )
    end

    it 'resends the persisted session-creation values to POST /checkout/api/status, logging the request/response' do
      captured_request = nil
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return({ responseData: { status: 'success', responseCode: '00' } }.to_json)
      allow(Net::HTTP).to receive(:start) do |host, _port, **kwargs, &block|
        expect(host).to eq('sandbox-api.kuickpay.com')
        expect(kwargs[:use_ssl]).to be(true)
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) { |request| captured_request = request }.and_return(response)
        block.call(http)
      end
      allow(Rails.logger).to receive(:info)

      result = adapter.verify_status(payment:)

      expect(captured_request.path).to eq('/checkout/api/status')
      body = JSON.parse(captured_request.body)
      expect(body).to eq(
        'companyid' => 'merchant-1',
        'orderid' => 'PAY-ORDER-123',
        'sessionid' => 'session-123',
        'amount' => '1500.00',
        'amountPayable' => '1500.00',
        'timestamp' => '2026-08-31T09:00:00Z',
        'signature' => 'persisted-signature=='
      )
      expect(result.http_status).to eq(200)
      expect(result.body).to eq({ 'responseData' => { 'status' => 'success', 'responseCode' => '00' } })
      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(%r{\[KuickPay\]\[verify_status\] request url=.*/checkout/api/status.*response status=200})
      )
    end

    it 'returns the raw response body when it is not valid JSON, without raising' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('not-json')
      allow(Net::HTTP).to receive(:start).and_return(response)

      result = adapter.verify_status(payment:)

      expect(result.body).to eq('not-json')
    end

    it 'raises when the session-creation snapshot was never persisted for this payment' do
      incomplete_payment = build_stubbed(:payment, provider_order_id: 'PAY-ORDER-123', provider_request_timestamp: nil)

      expect { adapter.verify_status(payment: incomplete_payment) }.to raise_error(PaymentCheckoutUnavailableError)
    end

    it 'raises when KuickPay is not configured for requests' do
      unconfigured = instance_double(Payments::Configuration, kuickpay_enabled?: false)

      expect do
        described_class.new(configuration: unconfigured).verify_status(payment:)
      end.to raise_error(PaymentCheckoutUnavailableError)
    end

    it 'raises on a transport failure, logging a warning' do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'getaddrinfo failed')
      allow(Rails.logger).to receive(:warn)

      expect { adapter.verify_status(payment:) }.to raise_error(PaymentCheckoutUnavailableError)
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/verify_status request failed/))
    end
  end

  it 'parses a signed notification and rejects an invalid signature' do
    payload = {
      'orderid' => 'PAY-ORDER-123',
      'transactionid' => 'TXN-1',
      'amount' => '1500.0',
      'currency' => 'pkr',
      'status' => 'success',
      'responsecode' => '00'
    }
    signature_data = 'PAY-ORDER-123TXN-11500.0SUCCESS00'
    payload['signature'] = OpenSSL::HMAC.hexdigest('SHA256', 'secret-1', signature_data)

    notification = adapter.parse_notification!(event_source: 'callback', params: payload)

    expect(notification.provider_code).to eq('kuickpay')
    expect(notification.currency_code).to eq('PKR')
    expect(notification.provider_status_code).to eq('SUCCESS')
    expect(notification.provider_transaction_id).to eq('TXN-1')

    payload['signature'] = 'bad-signature'
    expect do
      adapter.parse_notification!(event_source: 'callback', params: payload)
    end.to raise_error(PaymentSignatureInvalidError)
  end
end

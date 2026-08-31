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

  it 'builds a checkout session from a successful KuickPay response' do
    payment = build_stubbed(:payment, public_id: 'payment-public-id', provider_order_id: 'PAY-ORDER-123')
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({
      success: true,
      responseData: {
        sessionID: 'session-1',
        redirectURL: 'https://checkout.example.test/session-1'
      }
    }.to_json)

    allow(Net::HTTP).to receive(:start).and_return(response)

    travel_to(Time.zone.parse('2026-08-31T09:00:00Z')) do
      session = adapter.create_checkout_session(payment:, amount: BigDecimal('1500'), currency_code: 'PKR')

      expect(session.provider_code).to eq('kuickpay')
      expect(session.session_id).to eq('session-1')
      expect(session.checkout_url).to eq('https://checkout.example.test/session-1')
      expect(session.expires_at).to eq(Time.zone.parse('2026-08-31T09:30:00Z'))
    end
  end

  it 'fails safely when KuickPay returns a non-success response or invalid json' do
    payment = build_stubbed(:payment, provider_order_id: 'PAY-ORDER-123')
    unsuccessful = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(unsuccessful).to receive(:body).and_return({ success: false }.to_json)

    allow(Net::HTTP).to receive(:start).and_return(unsuccessful)
    expect do
      adapter.create_checkout_session(payment:, amount: BigDecimal('1500'), currency_code: 'PKR')
    end.to raise_error(PaymentCheckoutUnavailableError)

    allow(unsuccessful).to receive(:body).and_return('not-json')
    expect do
      adapter.create_checkout_session(payment:, amount: BigDecimal('1500'), currency_code: 'PKR')
    end.to raise_error(PaymentCheckoutUnavailableError)
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

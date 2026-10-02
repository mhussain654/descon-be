# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::KuickpaySessionPayloadBuilder do
  subject(:builder) do
    described_class.new(configuration:, payment:, amount: BigDecimal('1500'), currency_code: 'PKR')
  end

  let(:payment) { build_stubbed(:payment, public_id: 'payment-public-id', provider_order_id: 'PAY-ORDER-123') }
  let(:configuration) do
    instance_double(
      Payments::Configuration,
      kuickpay_company_id: 'merchant-1',
      kuickpay_secured_key: 'secret-1',
      kuickpay_return_url: 'https://app.example.test/return'
    )
  end

  it 'builds a signed KuickPay session payload with the documented fields only, no extra currency field' do
    travel_to(Time.zone.parse('2026-08-31T09:00:00Z')) do
      payload = builder.call

      expect(payload).to eq(
        companyid: 'merchant-1',
        orderid: 'PAY-ORDER-123',
        amount: '1500.00',
        amountPayable: '1500.00',
        timestamp: '2026-08-31T09:00:00Z',
        transactiondescription: 'Descon onboarding fee payment-public-id',
        returnurl: 'https://app.example.test/return?orderid=PAY-ORDER-123',
        signature: Base64.strict_encode64(
          OpenSSL::HMAC.digest('SHA256', 'secret-1', 'merchant-1|PAY-ORDER-123|1500.00|1500.00|2026-08-31T09:00:00Z')
        )
      )
    end
  end

  it 'preserves an existing query string on the configured return URL when embedding orderid' do
    configuration_with_query = instance_double(
      Payments::Configuration,
      kuickpay_company_id: 'merchant-1',
      kuickpay_secured_key: 'secret-1',
      kuickpay_return_url: 'https://app.example.test/return?env=sandbox'
    )
    builder_with_query = described_class.new(
      configuration: configuration_with_query, payment:, amount: BigDecimal('1500'), currency_code: 'PKR'
    )

    expect(builder_with_query.call[:returnurl]).to eq('https://app.example.test/return?env=sandbox&orderid=PAY-ORDER-123')
  end

  it 'URL-encodes the orderid embedded in the return URL' do
    odd_order_payment = build_stubbed(:payment, public_id: 'payment-public-id', provider_order_id: 'PAY ORDER/123')
    odd_builder = described_class.new(configuration:, payment: odd_order_payment, amount: BigDecimal('1500'),
                                      currency_code: 'PKR')

    expect(odd_builder.call[:returnurl]).to eq('https://app.example.test/return?orderid=PAY+ORDER%2F123')
  end

  it 'exposes the exact request values as a snapshot for later byte-for-byte reuse against the Status API' do
    travel_to(Time.zone.parse('2026-08-31T09:00:00Z')) do
      payload = builder.call

      expect(builder.request_snapshot).to eq(
        provider_request_timestamp: payload.fetch(:timestamp),
        provider_request_signature: payload.fetch(:signature),
        provider_amount_payable: payload.fetch(:amountPayable)
      )
    end
  end
end

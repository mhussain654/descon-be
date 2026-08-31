# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::KuickpaySessionPayloadBuilder do
  it 'builds a signed KuickPay session payload with formatted amount and timestamp' do
    payment = build_stubbed(:payment, public_id: 'payment-public-id', provider_order_id: 'PAY-ORDER-123')
    configuration = instance_double(
      Payments::Configuration,
      kuickpay_company_id: 'merchant-1',
      kuickpay_secured_key: 'secret-1',
      kuickpay_return_url: 'https://app.example.test/return'
    )

    travel_to(Time.zone.parse('2026-08-31T09:00:00Z')) do
      payload = described_class.new(
        configuration:,
        payment:,
        amount: BigDecimal('1500'),
        currency_code: 'PKR'
      ).call

      expect(payload).to include(
        companyid: 'merchant-1',
        orderid: 'PAY-ORDER-123',
        amount: '1500.00',
        amountPayable: '1500.00',
        transactiondescription: 'Descon onboarding fee payment-public-id',
        returnurl: 'https://app.example.test/return',
        currency: 'PKR',
        timestamp: '20260831090000'
      )
      expect(payload[:signature]).to eq(
        OpenSSL::HMAC.hexdigest('SHA256', 'secret-1', 'merchant-1|PAY-ORDER-123|1500.00|1500.00|20260831090000')
      )
    end
  end
end

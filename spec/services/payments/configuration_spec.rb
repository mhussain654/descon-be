# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Configuration do
  around do |example|
    original_env = ENV.to_h
    example.run
  ensure
    ENV.replace(original_env)
  end

  it 'returns safe defaults in test' do
    ENV.delete('PAYMENT_PROVIDER')
    ENV.delete('ONBOARDING_FEE_AMOUNT')
    ENV.delete('PAYMENT_CURRENCY_CODE')
    ENV.delete('PAYMENT_CHECKOUT_EXPIRES_IN_MINUTES')
    ENV.delete('PAYMENT_MOCK_BASE_URL')
    ENV.delete('PAYMENT_MOCK_SECRET')
    ENV.delete('KUICKPAY_ENABLED')
    ENV.delete('KUICKPAY_COMPANY_ID')
    ENV.delete('KUICKPAY_SECURED_KEY')
    ENV.delete('KUICKPAY_BASE_URL')
    ENV.delete('KUICKPAY_RETURN_URL')
    ENV.delete('KUICKPAY_OPEN_TIMEOUT_SECONDS')
    ENV.delete('KUICKPAY_READ_TIMEOUT_SECONDS')

    configuration = described_class.new

    expect(configuration.provider_code).to eq('mock_hosted_checkout')
    expect(configuration.amount).to eq(BigDecimal('1500.00'))
    expect(configuration.currency_code).to eq('PKR')
    expect(configuration.checkout_expires_in_minutes).to eq(30)
    expect(configuration.mock_base_url).to eq('https://mock-payments.example.test/checkout')
    expect(configuration.mock_secret).to eq('mock-provider-secret')
    expect(configuration.kuickpay_enabled?).to be(false)
    expect(configuration.kuickpay_company_id).to be_nil
    expect(configuration.kuickpay_secured_key).to be_nil
    expect(configuration.kuickpay_base_url).to eq('https://sandbox-api.kuickpay.com')
    expect(configuration.kuickpay_return_url).to be_nil
    expect(configuration.kuickpay_open_timeout).to eq(5)
    expect(configuration.kuickpay_read_timeout).to eq(10)
  end

  it 'normalizes configured environment values' do
    ENV['PAYMENT_PROVIDER'] = ' KUICKPAY '
    ENV['ONBOARDING_FEE_AMOUNT'] = '1700.50'
    ENV['PAYMENT_CURRENCY_CODE'] = ' pkr '
    ENV['PAYMENT_CHECKOUT_EXPIRES_IN_MINUTES'] = '45'
    ENV['PAYMENT_MOCK_BASE_URL'] = 'https://example.test/mock'
    ENV['PAYMENT_MOCK_SECRET'] = 'secret-1'
    ENV['KUICKPAY_ENABLED'] = 'true'
    ENV['KUICKPAY_COMPANY_ID'] = ' company-id '
    ENV['KUICKPAY_SECURED_KEY'] = ' secured-key '
    ENV['KUICKPAY_BASE_URL'] = ' https://merchant.example.test '
    ENV['KUICKPAY_RETURN_URL'] = ' https://app.example.test/return '
    ENV['KUICKPAY_OPEN_TIMEOUT_SECONDS'] = '9'
    ENV['KUICKPAY_READ_TIMEOUT_SECONDS'] = '12'

    configuration = described_class.new

    expect(configuration.provider_code).to eq('kuickpay')
    expect(configuration.amount).to eq(BigDecimal('1700.50'))
    expect(configuration.currency_code).to eq('PKR')
    expect(configuration.checkout_expires_in_minutes).to eq(45)
    expect(configuration.mock_base_url).to eq('https://example.test/mock')
    expect(configuration.mock_secret).to eq('secret-1')
    expect(configuration.kuickpay_enabled?).to be(true)
    expect(configuration.kuickpay_company_id).to eq('company-id')
    expect(configuration.kuickpay_secured_key).to eq('secured-key')
    expect(configuration.kuickpay_base_url).to eq('https://merchant.example.test')
    expect(configuration.kuickpay_return_url).to eq('https://app.example.test/return')
    expect(configuration.kuickpay_open_timeout).to eq(9)
    expect(configuration.kuickpay_read_timeout).to eq(12)
  end
end

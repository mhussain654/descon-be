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
    ENV.delete('ONBOARDING_FEE_AMOUNT')
    ENV.delete('PAYMENT_CURRENCY_CODE')
    ENV.delete('PAYMENT_CHECKOUT_EXPIRES_IN_MINUTES')
    ENV.delete('KUICKPAY_ENABLED')
    ENV.delete('KUICKPAY_COMPANY_ID')
    ENV.delete('KUICKPAY_RETURN_URL')
    ENV.delete('KUICKPAY_OPEN_TIMEOUT_SECONDS')
    ENV.delete('KUICKPAY_READ_TIMEOUT_SECONDS')

    configuration = described_class.new

    expect(configuration.provider_code).to eq('kuickpay')
    expect(configuration.amount).to eq(BigDecimal('1500.00'))
    expect(configuration.currency_code).to eq('PKR')
    expect(configuration.checkout_expires_in_minutes).to eq(30)
    expect(configuration.kuickpay_enabled?).to be(false)
    expect(configuration.kuickpay_company_id).to be_nil
    # Test env's config/kuickpay.yml always has a fake secured_key (test
    # never reaches KuickPay) -- the real secret comes from credentials,
    # never from an ENV var.
    expect(configuration.kuickpay_secured_key).to eq('test-kuickpay-secured-key')
    expect(configuration.kuickpay_base_url).to eq('https://sandbox-api.kuickpay.com')
    expect(configuration.kuickpay_return_url).to be_nil
    expect(configuration.kuickpay_open_timeout).to eq(5)
    expect(configuration.kuickpay_read_timeout).to eq(10)
  end

  it 'normalizes configured environment values' do
    ENV['ONBOARDING_FEE_AMOUNT'] = '1700.50'
    ENV['PAYMENT_CURRENCY_CODE'] = ' pkr '
    ENV['PAYMENT_CHECKOUT_EXPIRES_IN_MINUTES'] = '45'
    ENV['KUICKPAY_ENABLED'] = 'true'
    ENV['KUICKPAY_COMPANY_ID'] = ' company-id '
    ENV['KUICKPAY_BASE_URL'] = 'https://elsewhere.example.test'
    ENV['KUICKPAY_HYBRID_BASE_URL'] = 'https://elsewhere.example.test'
    ENV['KUICKPAY_HYBRID_USERNAME'] = 'env-login'
    ENV['KUICKPAY_RETURN_URL'] = ' https://app.example.test/return '
    ENV['KUICKPAY_OPEN_TIMEOUT_SECONDS'] = '9'
    ENV['KUICKPAY_READ_TIMEOUT_SECONDS'] = '12'

    configuration = described_class.new

    expect(configuration.provider_code).to eq('kuickpay')
    expect(configuration.amount).to eq(BigDecimal('1700.50'))
    expect(configuration.currency_code).to eq('PKR')
    expect(configuration.checkout_expires_in_minutes).to eq(45)
    expect(configuration.kuickpay_enabled?).to be(true)
    expect(configuration.kuickpay_company_id).to eq('company-id')
    # secured_key is intentionally unaffected by ENV -- it comes only from
    # config/kuickpay.yml/credentials now (see the "config/kuickpay.yml"
    # example group below).
    expect(configuration.kuickpay_secured_key).to eq('test-kuickpay-secured-key')
    # The KuickPay hosts are fixed in config/kuickpay.yml; an ENV var cannot move them.
    expect(configuration.kuickpay_base_url).to eq('https://sandbox-api.kuickpay.com')
    expect(configuration.kuickpay_hybrid_base_url).to eq('https://uat-adminapi.kuickpay.com')
    # Logins come only from the credentials, never from ENV.
    expect(configuration.kuickpay_hybrid_username).to eq('test-hybrid-user')
    expect(configuration.kuickpay_return_url).to eq('https://app.example.test/return')
    expect(configuration.kuickpay_open_timeout).to eq(9)
    expect(configuration.kuickpay_read_timeout).to eq(12)
  end

  describe 'kuickpay secured_key, sourced from credentials rather than ENV' do
    def with_kuickpay_settings(values)
      allow(Rails.application).to receive(:config_for).with(:kuickpay).and_return(values)
    end

    it 'reads the secured_key from whatever config/kuickpay.yml resolves to' do
      with_kuickpay_settings(company_id: 'company-1', secured_key: 'from-credentials', base_url: '', open_timeout: 5,
                             read_timeout: 10)

      expect(described_class.new.kuickpay_secured_key).to eq('from-credentials')
    end

    it 'treats a blank secured_key as unset' do
      with_kuickpay_settings(company_id: 'company-1', secured_key: '', base_url: '', open_timeout: 5, read_timeout: 10)

      expect(described_class.new.kuickpay_secured_key).to be_nil
    end
  end

  describe 'config/kuickpay.yml' do
    it 'renders for the test environment with a fake secured_key and the default timeouts' do
      loaded = Rails.application.config_for(:kuickpay)

      expect(loaded).to include(secured_key: 'test-kuickpay-secured-key', open_timeout: 5, read_timeout: 10)
    end
  end

  describe 'voucher (KuickPay Hybrid) settings' do
    it 'is off by default, with a 14-day voucher and the fixed test login' do
      %w[KUICKPAY_VOUCHER_ENABLED KUICKPAY_INSTITUTION_ID KUICKPAY_COMPANY_ID
         PAYMENT_VOUCHER_VALID_DAYS PAYMENT_VOUCHER_FALLBACK_EMAIL].each { |key| ENV.delete(key) }

      configuration = described_class.new

      expect(configuration).not_to be_kuickpay_voucher_enabled
      expect(configuration.kuickpay_hybrid_base_url).to eq('https://uat-adminapi.kuickpay.com')
      expect([configuration.kuickpay_hybrid_username, configuration.kuickpay_hybrid_password])
        .to eq(%w[test-hybrid-user test-hybrid-password])
      expect([configuration.kuickpay_payment_status_username, configuration.kuickpay_payment_status_password])
        .to eq(%w[test-payment-status-user test-payment-status-password])
      expect(configuration.voucher_valid_days).to eq(14)
      expect(configuration.voucher_fallback_email).to eq('no-reply@descon-mps.com')
    end

    it 'reads the switch, institution id, validity and fallback email from the environment' do
      ENV['KUICKPAY_VOUCHER_ENABLED'] = 'true'
      ENV['KUICKPAY_INSTITUTION_ID'] = '00008'
      ENV['PAYMENT_VOUCHER_VALID_DAYS'] = '7'
      ENV['PAYMENT_VOUCHER_FALLBACK_EMAIL'] = ' fees@example.test '

      configuration = described_class.new

      expect(configuration).to be_kuickpay_voucher_enabled
      expect(configuration.kuickpay_institution_id).to eq('00008')
      expect(configuration.voucher_valid_days).to eq(7)
      expect(configuration.voucher_fallback_email).to eq('fees@example.test')
    end

    it 'uses the company id as the institution id when none is set' do
      ENV.delete('KUICKPAY_INSTITUTION_ID')
      ENV['KUICKPAY_COMPANY_ID'] = '01234'

      expect(described_class.new.kuickpay_institution_id).to eq('01234')
    end
  end
end

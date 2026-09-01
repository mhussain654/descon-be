# frozen_string_literal: true

module Payments
  class Configuration
    DEFAULT_PROVIDER_BY_ENV = {
      'test' => 'mock_hosted_checkout',
      'development' => 'mock_hosted_checkout',
      'production' => 'kuickpay'
    }.freeze

    def provider_code
      ENV['PAYMENT_PROVIDER'].to_s.strip.downcase.presence || DEFAULT_PROVIDER_BY_ENV.fetch(Rails.env, 'kuickpay')
    end

    def amount
      BigDecimal(ENV.fetch('ONBOARDING_FEE_AMOUNT', '1500.00'))
    end

    def currency_code
      ENV.fetch('PAYMENT_CURRENCY_CODE', 'PKR').strip.upcase
    end

    def checkout_expires_in_minutes
      ENV.fetch('PAYMENT_CHECKOUT_EXPIRES_IN_MINUTES', 30).to_i
    end

    def mock_base_url
      ENV.fetch('PAYMENT_MOCK_BASE_URL', 'https://mock-payments.example.test/checkout')
    end

    def mock_secret
      ENV.fetch('PAYMENT_MOCK_SECRET', 'mock-provider-secret')
    end

    def kuickpay_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('KUICKPAY_ENABLED', 'false'))
    end

    def kuickpay_company_id
      ENV['KUICKPAY_COMPANY_ID'].to_s.strip.presence
    end

    def kuickpay_secured_key
      ENV['KUICKPAY_SECURED_KEY'].to_s.strip.presence
    end

    def kuickpay_base_url
      ENV.fetch('KUICKPAY_BASE_URL', 'https://sandbox-api.kuickpay.com').strip
    end

    def kuickpay_return_url
      ENV['KUICKPAY_RETURN_URL'].to_s.strip.presence
    end

    # Where HostedCheckoutReturnsController sends the candidate's browser
    # once it has processed the provider's return notification -- a
    # frontend route (e.g. /payment/pending), never the API host itself.
    # The frontend must treat this only as "come check payment status
    # again," never as proof of success on its own.
    def frontend_payment_return_url
      ENV['FRONTEND_PAYMENT_RETURN_URL'].to_s.strip.presence
    end

    def kuickpay_open_timeout
      ENV.fetch('KUICKPAY_OPEN_TIMEOUT_SECONDS', 5).to_i
    end

    def kuickpay_read_timeout
      ENV.fetch('KUICKPAY_READ_TIMEOUT_SECONDS', 10).to_i
    end
  end
end

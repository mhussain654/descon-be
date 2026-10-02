# frozen_string_literal: true

module Payments
  class Configuration
    # KuickPay is the only integrated provider -- see KUICKPAY_ENABLED below
    # for the operational kill switch (the mechanism that actually needs to
    # vary per environment/deploy).
    def provider_code = 'kuickpay'

    def amount
      BigDecimal(ENV.fetch('ONBOARDING_FEE_AMOUNT', '1500.00'))
    end

    def currency_code
      ENV.fetch('PAYMENT_CURRENCY_CODE', 'PKR').strip.upcase
    end

    def checkout_expires_in_minutes
      ENV.fetch('PAYMENT_CHECKOUT_EXPIRES_IN_MINUTES', 30).to_i
    end

    # Per-server kill switch/toggle -- stays a plain ENV var, same as
    # provider_code above, rather than moving into config/kuickpay.yml.
    def kuickpay_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('KUICKPAY_ENABLED', 'false'))
    end

    def kuickpay_company_id
      kuickpay_setting(:company_id)
    end

    def kuickpay_secured_key
      kuickpay_setting(:secured_key)
    end

    def kuickpay_base_url
      kuickpay_setting(:base_url) || 'https://sandbox-api.kuickpay.com'
    end

    def kuickpay_return_url
      kuickpay_setting(:return_url)
    end

    # Where the candidate's browser is redirected after HostedCheckoutReturnsController
    # processes the signed provider return -- the frontend's dedicated, unauthenticated
    # payment-pending page (never a JSON error/success body -- see that controller).
    def frontend_payment_return_url
      ENV['FRONTEND_PAYMENT_RETURN_URL'].to_s.strip.presence
    end

    def kuickpay_open_timeout
      kuickpay_setting(:open_timeout).to_i
    end

    def kuickpay_read_timeout
      kuickpay_setting(:read_timeout).to_i
    end

    private

    def kuickpay_setting(key)
      @kuickpay_settings ||= Rails.application.config_for(:kuickpay)
      @kuickpay_settings[key].to_s.strip.presence
    end
  end
end

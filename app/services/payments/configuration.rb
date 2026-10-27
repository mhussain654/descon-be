# frozen_string_literal: true

module Payments
  class Configuration
    # KuickPay is the only integrated provider -- see KUICKPAY_ENABLED below
    # for the operational kill switch (the mechanism that actually needs to
    # vary per environment/deploy).
    def provider_code = 'kuickpay'

    def amount
      OnboardingFeeSetting.current.amount
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
      kuickpay_setting(:base_url)
    end

    def kuickpay_return_url
      kuickpay_setting(:return_url)
    end

    # Voucher (consumer number) payments -- wallet / bank-app payment with a code. Its own
    # kill switch, separate from the hosted card checkout's KUICKPAY_ENABLED.
    def kuickpay_voucher_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('KUICKPAY_VOUCHER_ENABLED', 'false'))
    end

    def kuickpay_hybrid_base_url
      kuickpay_setting(:hybrid_base_url)
    end

    def kuickpay_hybrid_username
      kuickpay_setting(:hybrid_username)
    end

    def kuickpay_hybrid_password
      kuickpay_setting(:hybrid_password)
    end

    # The login for Bill Payment Bulk Inquiry (checking which vouchers were paid). KuickPay
    # issues it separately from the Insert Voucher login, and the voucher login is refused
    # there ("User is not Active"), so there is deliberately no fallback to it.
    def kuickpay_payment_status_username
      kuickpay_setting(:payment_status_username)
    end

    def kuickpay_payment_status_password
      kuickpay_setting(:payment_status_password)
    end

    def kuickpay_institution_id
      kuickpay_setting(:institution_id) || kuickpay_company_id
    end

    # How long an unpaid voucher stays payable (also the due date: no late fee).
    def voucher_valid_days
      ENV.fetch('PAYMENT_VOUCHER_VALID_DAYS', 14).to_i
    end

    # KuickPay requires an email for every voucher; candidates have none on file.
    def voucher_fallback_email
      ENV.fetch('PAYMENT_VOUCHER_FALLBACK_EMAIL', 'no-reply@descon-mps.com').strip
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

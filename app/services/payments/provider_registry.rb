# frozen_string_literal: true

module Payments
  class ProviderRegistry
    def self.fetch(provider_code = Payments::Configuration.new.provider_code)
      configuration = Payments::Configuration.new
      normalized_code = provider_code.to_s.strip.downcase.presence || configuration.provider_code
      reject_mock_provider!(normalized_code)

      case normalized_code
      when 'mock_hosted_checkout' then Payments::Providers::MockHostedCheckoutAdapter.new(configuration:)
      when 'kuickpay' then Payments::Providers::KuickpayHostedCheckoutAdapter.new(configuration:)
      else
        raise ProviderNotConfiguredError, "Unknown PAYMENT_PROVIDER: #{normalized_code.inspect}"
      end
    end

    def self.reject_mock_provider!(provider_code)
      return unless %w[production staging].include?(Rails.env.to_s) && provider_code == 'mock_hosted_checkout'

      raise ProviderNotConfiguredError, 'PAYMENT_PROVIDER=mock_hosted_checkout is not allowed outside test/development'
    end
  end
end

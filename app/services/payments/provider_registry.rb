# frozen_string_literal: true

module Payments
  class ProviderRegistry
    def self.fetch(provider_code = Payments::Configuration.new.provider_code)
      configuration = Payments::Configuration.new
      normalized_code = provider_code.to_s.strip.downcase.presence || configuration.provider_code

      case normalized_code
      when 'kuickpay' then Payments::Providers::KuickpayHostedCheckoutAdapter.new(configuration:)
      else
        raise ProviderNotConfiguredError, "Unknown payment provider: #{normalized_code.inspect}"
      end
    end
  end
end

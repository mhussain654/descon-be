# frozen_string_literal: true

module Payments
  module Providers
    class MockHostedCheckoutAdapter
      include Payments::Providers::SignedNotificationSupport

      def initialize(configuration:)
        @configuration = configuration
      end

      def create_checkout_session(payment:, **)
        expires_at = Time.current + @configuration.checkout_expires_in_minutes.minutes
        Payments::Providers::CheckoutSession.new(
          provider_code: provider_code,
          session_id: "mock-session-#{payment.public_id}",
          checkout_url: "#{@configuration.mock_base_url}?orderid=#{payment.provider_order_id}",
          expires_at:
        )
      end

      def parse_notification!(event_source:, params:)
        payload = canonical_payload(params)
        verify_signature!(provided: params.fetch('signature').to_s, expected: sign_notification(payload))
        build_notification(event_source:, payload:)
      end

      def sign_notification(payload)
        OpenSSL::HMAC.hexdigest('SHA256', @configuration.mock_secret, payload.values.join('|'))
      end

      def available? = !Rails.env.production?

      def provider_code = 'mock_hosted_checkout'

      private

      def canonical_payload(params)
        {
          'orderid' => params.fetch('orderid').to_s,
          'transactionid' => params['transactionid'].to_s.presence,
          'amount' => params.fetch('amount').to_s,
          'currency' => params.fetch('currency').to_s.upcase,
          'status' => params.fetch('status').to_s.upcase,
          'responsecode' => params.fetch('responsecode').to_s
        }
      end
    end
  end
end

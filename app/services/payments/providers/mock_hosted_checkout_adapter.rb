# frozen_string_literal: true

module Payments
  module Providers
    class MockHostedCheckoutAdapter
      include Payments::Providers::SignedNotificationSupport

      SIMULATED_OUTCOME_CODES = {
        'success' => %w[SUCCESS 00],
        'failed' => %w[FAILED 05],
        'cancelled' => %w[CANCELLED 17]
      }.freeze

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

      # Builds a correctly signed return payload for MockCheckoutsController
      # to link to, simulating what a real provider would send back after
      # the candidate finishes on its hosted page. Routed through the same
      # canonical_payload/sign_notification a real inbound notification
      # would use, so it can never drift from what #parse_notification!
      # actually accepts.
      def simulated_return_params(payment:, outcome:)
        raw = simulated_raw_params(payment:, outcome:)
        payload = canonical_payload(raw)
        payload.merge('signature' => sign_notification(payload))
      end

      private

      def simulated_raw_params(payment:, outcome:)
        status, responsecode = SIMULATED_OUTCOME_CODES.fetch(outcome)
        {
          'orderid' => payment.provider_order_id,
          'transactionid' => "MOCK-#{SecureRandom.hex(6)}",
          'amount' => format('%.2f', payment.amount),
          'currency' => payment.currency_code,
          'status' => status,
          'responsecode' => responsecode
        }
      end

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

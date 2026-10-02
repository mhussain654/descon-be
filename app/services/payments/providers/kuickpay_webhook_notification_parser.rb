# frozen_string_literal: true

module Payments
  module Providers
    # Parses and signature-verifies the webhook/callback-shaped payload
    # (orderid/transactionid/amount/currency/status/responsecode/signature)
    # that KuickpayHostedCheckoutAdapter#parse_notification! still supports
    # for event_source: 'callback' -- kept separate from the adapter itself
    # so its real HTTP-calling responsibilities (Create Session, Verify
    # Status) aren't tangled up with this legacy/possibly-unused shape. See
    # that method's own KNOWN GAP comment for why 'return' no longer uses this.
    class KuickpayWebhookNotificationParser
      include Payments::Providers::SignedNotificationSupport

      def initialize(configuration:)
        @configuration = configuration
      end

      def call(event_source:, params:)
        payload = canonical_notification_payload(params)
        verify_signature!(provided: params.fetch('signature').to_s, expected: notification_signature(payload))
        build_notification(event_source:, payload:)
      end

      def provider_code = 'kuickpay'

      private

      def canonical_notification_payload(params)
        {
          'orderid' => params.fetch('orderid').to_s,
          'transactionid' => params['transactionid'].to_s.presence,
          'amount' => params.fetch('amount').to_s,
          'currency' => params['currency'].to_s.upcase.presence,
          'status' => params.fetch('status').to_s.upcase,
          'responsecode' => params.fetch('responsecode').to_s
        }
      end

      def notification_signature(payload)
        data = [
          payload.fetch('orderid'),
          payload['transactionid'].to_s,
          payload.fetch('amount'),
          payload.fetch('status'),
          payload.fetch('responsecode')
        ].join
        OpenSSL::HMAC.hexdigest('SHA256', @configuration.kuickpay_secured_key.to_s, data)
      end
    end
  end
end

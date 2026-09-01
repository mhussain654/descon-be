# frozen_string_literal: true

module Payments
  module Providers
    module SignedNotificationSupport
      private

      def build_notification(event_source:, payload:)
        Payments::Providers::Notification.new(notification_attributes(event_source:, payload:))
      end

      def verify_signature!(provided:, expected:)
        return if signature_valid?(provided:, expected:)

        raise PaymentSignatureInvalidError
      end

      def signature_valid?(provided:, expected:)
        provided.bytesize == expected.bytesize &&
          ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      def notification_attributes(event_source:, payload:)
        notification_identity_attributes(event_source:, payload:).merge(
          provider_order_id: payload.fetch('orderid'),
          provider_transaction_id: payload['transactionid'],
          provider_status_code: payload.fetch('status'),
          provider_response_code: payload.fetch('responsecode'),
          amount: BigDecimal(payload.fetch('amount')),
          currency_code: payload['currency'],
          occurred_at: Time.current,
          payload:
        )
      end

      def notification_identity_attributes(event_source:, payload:)
        {
          provider_code:,
          event_source: event_source.to_s,
          event_key: Digest::SHA256.hexdigest(payload.values.join('|'))
        }
      end
    end
  end
end

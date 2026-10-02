# frozen_string_literal: true

module Payments
  module Providers
    # Builds the POST /checkout/api/status request body, mirroring
    # KuickpaySessionPayloadBuilder's shape for the sibling Create Session
    # call. Per KuickPay's guide, the Status API re-validates the exact
    # request used to create the session -- so every value here is read back
    # from what CheckoutSessionPersister already persisted on the Payment at
    # session-creation time, never recomputed (see payments.
    # provider_request_timestamp's migration comment).
    class KuickpayStatusCheckPayloadBuilder
      def initialize(configuration:, payment:)
        @configuration = configuration
        @payment = payment
      end

      # True once a session has actually been created for this payment --
      # provider_session_id and the three snapshot fields are only ever
      # populated together, by CheckoutSessionPersister right after a
      # successful create_checkout_session.
      def snapshot_present?
        @payment.provider_session_id.present? &&
          @payment.provider_order_id.present? &&
          @payment.provider_amount_payable.present? &&
          @payment.provider_request_timestamp.present? &&
          @payment.provider_request_signature.present?
      end

      # `companyid` is included for parity with the Create Session body;
      # KuickPay's guide does not explicitly confirm it's required here, but
      # Create Session sends it alongside the same signature scheme and
      # Basic Auth already carries it too, so omitting it would be the
      # riskier guess.
      #
      # `sessionid` added 2026-10-01: a real sandbox call sending every
      # documented field *except* this one got back `{"status":"failure",
      # "responseCode":"01","responseDescription":"Session not found"}` for a
      # session KuickPay itself had just confirmed creating, and where the
      # candidate had completed full checkout (card entry + 3DS) on
      # KuickPay's hosted page beforehand -- the wording ("Session not
      # found", not "Order not found") strongly suggests the lookup key is
      # their own issued sessionID, not our orderid alone. Sent in addition
      # to orderid, not instead of it, since the guide still documents
      # orderid as part of this request and the signature is unaffected
      # either way (see #signature in KuickpaySessionPayloadBuilder -- the
      # canonical string never included sessionid to begin with).
      def call
        {
          companyid: @configuration.kuickpay_company_id,
          orderid: @payment.provider_order_id,
          sessionid: @payment.provider_session_id,
          amount: @payment.provider_amount_payable,
          amountPayable: @payment.provider_amount_payable,
          timestamp: @payment.provider_request_timestamp,
          signature: @payment.provider_request_signature
        }
      end
    end
  end
end

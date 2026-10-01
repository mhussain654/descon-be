# frozen_string_literal: true

require 'net/http'

module Payments
  module Providers
    class KuickpayHostedCheckoutAdapter
      # Per KuickPay's own "KuickPay Merchant Integration Guide" (hosted
      # checkout) -- distinct from their BPS biller-inquiry API, which uses
      # a different base path (/api/v1/BillInquiry, /api/v1/BillPayment)
      # and is not what this adapter integrates with.
      CREATE_SESSION_PATH = '/checkout/api/session'

      # Per the guide's 4-step flow (Create Session -> Redirect -> Handle
      # Return -> Verify Status) and the adapter's own request-shape
      # understanding -- KuickPay's guide documents the request shape for
      # this call but never shows a sample response, so every call through
      # KuickpayHttpClient logs its full request/response verbatim rather
      # than assuming a response shape, until a real sandbox call confirms one.
      #
      # UNCONFIRMED PATH -- flagged, not silently assumed correct: the
      # guide's literal text says `/api/status`, but a real sandbox call to
      # exactly that path (2026-10-01) returned a plain IIS 404 ("File or
      # directory not found"), not a KuickPay API response -- meaning that
      # path does not exist on their server. Changed to `/checkout/api/status`
      # to mirror Create Session's confirmed-correct `/checkout/api/session`
      # prefix, on the hypothesis both endpoints share it -- this is our own
      # best guess, not confirmed by KuickPay. If a real call still 404s
      # here, this is the next thing to ask KuickPay directly: "what is the
      # exact Status API path?"
      VERIFY_STATUS_PATH = '/checkout/api/status'

      def initialize(configuration:)
        @configuration = configuration
        @http_client = Payments::Providers::KuickpayHttpClient.new(configuration:)
      end

      def create_checkout_session(payment:, amount:, currency_code:, **)
        raise PaymentCheckoutUnavailableError unless configured_for_requests?

        builder = payload_builder(payment:, amount:, currency_code:)
        body = perform_create_session_request(builder.call)
        build_checkout_session(response_data: body.fetch('responseData'), raw_response: body, builder:)
      end

      # Calls KuickPay's Status API with the exact orderid/amount/
      # amountPayable/timestamp/signature persisted verbatim at session
      # creation (KuickPay's guide: re-send the identical signed request
      # values, do not recompute them -- see
      # payments.provider_request_timestamp's migration comment). Every
      # request and response is logged in full (see #log_kuickpay_call) so a
      # real sandbox call's exact payload/response can be captured and
      # shared with KuickPay while their Status API response shape is still
      # unconfirmed. Returns the raw StatusCheckResponse -- callers decide
      # whether/how to interpret `body`, never this adapter.
      def verify_status(payment:)
        raise PaymentCheckoutUnavailableError unless configured_for_requests?

        builder = status_check_payload_builder(payment)
        raise PaymentCheckoutUnavailableError unless builder.snapshot_present?

        perform_verify_status_request(builder.call)
      end

      # KNOWN GAP -- flagged, not silently assumed away: KuickPay's own
      # "KuickPay Merchant Integration Guide" (hosted checkout, provided
      # directly by the client 2026-09-28) documents no server-to-server
      # webhook at all. Its 4-step flow is Create Session -> Redirect ->
      # Handle Return -> Verify Status, and the browser return
      # (event_source: 'return') carries only `status`, `orderid` and
      # `sessionid` -- unsigned, and explicitly "do not treat this redirect
      # as proof of payment on its own." This method still expects
      # amount/responsecode/signature (the shape `event_source: 'callback'`
      # would need for a real async webhook, if KuickPay's merchant portal
      # can be configured to send one -- unconfirmed), so calling it from a
      # real 'return' redirect raises a KeyError -- the return flow calls
      # #verify_status instead (see Payments::VerifyPaymentStatusService),
      # never this method, for event_source: 'return'.
      def parse_notification!(event_source:, params:)
        webhook_notification_parser.call(event_source:, params:)
      end

      def available? = configured_for_requests?

      def provider_code = 'kuickpay'

      private

      def build_checkout_session(response_data:, raw_response:, builder:)
        Payments::Providers::CheckoutSession.new(
          provider_code: provider_code,
          session_id: response_data.fetch('sessionID'),
          checkout_url: response_data.fetch('redirectURL'),
          expires_at: Time.current + @configuration.checkout_expires_in_minutes.minutes,
          raw_response:,
          **builder.request_snapshot
        )
      end

      def payload_builder(payment:, amount:, currency_code:)
        Payments::Providers::KuickpaySessionPayloadBuilder.new(
          configuration: @configuration,
          payment:,
          currency_code:,
          amount:
        )
      end

      def configured_for_requests?
        @configuration.kuickpay_enabled? &&
          @configuration.kuickpay_company_id.present? &&
          @configuration.kuickpay_secured_key.present? &&
          @configuration.kuickpay_return_url.present?
      end

      def webhook_notification_parser
        Payments::Providers::KuickpayWebhookNotificationParser.new(configuration: @configuration)
      end

      def perform_create_session_request(request_payload)
        response = @http_client.post(path: CREATE_SESSION_PATH, payload: request_payload, step: 'create_session')
        body = JSON.parse(response.body)
        return body if response.is_a?(Net::HTTPSuccess) && session_created?(body)

        reject_session!(body)
      rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error => e
        reject_session!("#{e.class}: #{e.message}")
      end

      def reject_session!(detail)
        Rails.logger.warn("KuickPay rejected session creation: #{detail.to_json.truncate(500)}")
        raise PaymentCheckoutUnavailableError
      end

      def status_check_payload_builder(payment)
        Payments::Providers::KuickpayStatusCheckPayloadBuilder.new(configuration: @configuration, payment:)
      end

      def perform_verify_status_request(request_payload)
        response = @http_client.post(path: VERIFY_STATUS_PATH, payload: request_payload, step: 'verify_status')
        Payments::Providers::StatusCheckResponse.new(
          http_status: response.code.to_i,
          body: parsed_or_raw_body(response.body)
        )
      rescue SocketError, SystemCallError, Timeout::Error => e
        Rails.logger.warn("KuickPay verify_status request failed: #{e.class}: #{e.message}")
        raise PaymentCheckoutUnavailableError
      end

      def parsed_or_raw_body(raw_body)
        JSON.parse(raw_body)
      rescue JSON::ParserError
        raw_body
      end

      # KuickPay's own guide documents a top-level `success: true` boolean,
      # but a real sandbox call (confirmed 2026-09-28) never returns one --
      # only `responseData.status == "success"` /
      # `responseData.responseCode == "00"`. Neither shape is trusted
      # exclusively, in case production ever does send the documented one.
      def session_created?(body)
        return true if body['success']

        response_data = body['responseData']
        return false unless response_data.is_a?(Hash)

        response_data['status'].to_s.casecmp('success').zero? || response_data['responseCode'] == '00'
      end
    end
  end
end

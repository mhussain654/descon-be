# frozen_string_literal: true

require 'net/http'

module Payments
  module Providers
    class KuickpayHostedCheckoutAdapter
      include Payments::Providers::SignedNotificationSupport

      # Per KuickPay's own "KuickPay Merchant Integration Guide" (hosted
      # checkout) -- distinct from their BPS biller-inquiry API, which uses
      # a different base path (/api/v1/BillInquiry, /api/v1/BillPayment)
      # and is not what this adapter integrates with.
      CREATE_SESSION_PATH = '/checkout/api/session'

      def initialize(configuration:)
        @configuration = configuration
      end

      def create_checkout_session(payment:, amount:, currency_code:, **)
        raise PaymentCheckoutUnavailableError unless configured_for_requests?

        builder = payload_builder(payment:, amount:, currency_code:)
        response_data = perform_create_session_request(builder.call).fetch('responseData')
        build_checkout_session(response_data:, builder:)
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
      # real 'return' redirect raises a KeyError today rather than
      # confirming payment. Completing this requires calling
      # POST /api/status (request shape documented; response shape is NOT
      # shown anywhere in the guide) with the exact orderid/amount/
      # amountPayable/timestamp/signature persisted at session creation
      # (see payments.provider_request_timestamp) and mapping its response
      # into a Notification -- not implemented pending a real Status API
      # response sample from KuickPay's Tech team.
      def parse_notification!(event_source:, params:)
        payload = canonical_notification_payload(params)
        verify_signature!(provided: params.fetch('signature').to_s, expected: notification_signature(payload))
        build_notification(event_source:, payload:)
      end

      def available? = configured_for_requests?

      def provider_code = 'kuickpay'

      private

      def build_checkout_session(response_data:, builder:)
        Payments::Providers::CheckoutSession.new(
          provider_code: provider_code,
          session_id: response_data.fetch('sessionID'),
          checkout_url: response_data.fetch('redirectURL'),
          expires_at: Time.current + @configuration.checkout_expires_in_minutes.minutes,
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

      def perform_create_session_request(request_payload)
        uri = URI.join(@configuration.kuickpay_base_url, CREATE_SESSION_PATH)
        response = http_response_for(uri, build_request(uri, request_payload))
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

      def build_request(uri, request_payload)
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(@configuration.kuickpay_company_id, @configuration.kuickpay_secured_key)
        request.content_type = 'application/json'
        request.body = request_payload.to_json
        request
      end

      def http_response_for(uri, request)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: @configuration.kuickpay_open_timeout,
          read_timeout: @configuration.kuickpay_read_timeout
        ) { |http| http.request(request) }
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

# frozen_string_literal: true

require 'net/http'

module Payments
  module Providers
    class KuickpayHostedCheckoutAdapter
      include Payments::Providers::SignedNotificationSupport

      CREATE_SESSION_PATH = '/api/session'

      def initialize(configuration:)
        @configuration = configuration
      end

      def create_checkout_session(payment:, amount:, currency_code:, **)
        raise PaymentCheckoutUnavailableError unless configured_for_requests?

        request_payload = create_session_payload(payment:, amount:, currency_code:)

        response = perform_create_session_request(request_payload)
        response_data = response.fetch('responseData')

        Payments::Providers::CheckoutSession.new(
          provider_code: provider_code,
          session_id: response_data.fetch('sessionID'),
          checkout_url: response_data.fetch('redirectURL'),
          expires_at: Time.current + @configuration.checkout_expires_in_minutes.minutes
        )
      end

      def parse_notification!(event_source:, params:)
        payload = canonical_notification_payload(params)
        verify_signature!(provided: params.fetch('signature').to_s, expected: notification_signature(payload))
        build_notification(event_source:, payload:)
      end

      def available? = configured_for_requests?

      def provider_code = 'kuickpay'

      private

      def create_session_payload(payment:, amount:, currency_code:)
        Payments::Providers::KuickpaySessionPayloadBuilder.new(
          configuration: @configuration,
          payment:,
          currency_code:,
          amount:
        ).call
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
        request = build_request(uri, request_payload)

        response = http_response_for(uri, request)
        body = JSON.parse(response.body)
        return body if response.is_a?(Net::HTTPSuccess) && body['success']

        raise PaymentCheckoutUnavailableError
      rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error
        raise PaymentCheckoutUnavailableError
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

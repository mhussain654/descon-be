# frozen_string_literal: true

require 'net/http'

module Payments
  module Providers
    # Shared HTTP request/response plumbing for every KuickpayHostedCheckoutAdapter
    # call (Create Session, Verify Status) -- Basic Auth, timeouts, and the
    # unconditional request/response logging every KuickPay call needs while
    # their Status API response shape is still unconfirmed (see
    # KuickpayHostedCheckoutAdapter#verify_status). Never logs the Authorization
    # header (Basic Auth carries the SecuredKey) or the configured secured_key
    # itself -- a request body's own `signature` field is derived from that
    # key, not the key itself, so it's safe to log.
    class KuickpayHttpClient
      def initialize(configuration:)
        @configuration = configuration
      end

      def post(path:, payload:, step:)
        uri = URI.join(@configuration.kuickpay_base_url, path)
        response = http_response_for(uri, build_request(uri, payload))
        log_call(step:, uri:, payload:, response:)
        response
      end

      private

      def build_request(uri, payload)
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(@configuration.kuickpay_company_id, @configuration.kuickpay_secured_key)
        request.content_type = 'application/json'
        request.body = payload.to_json
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

      def log_call(step:, uri:, payload:, response:)
        Rails.logger.info(
          "[KuickPay][#{step}] request url=#{uri} body=#{payload.to_json} " \
          "response status=#{response.code} body=#{response.body}"
        )
      end
    end
  end
end

# frozen_string_literal: true

require 'net/http'

module Payments
  module Providers
    # HTTP plumbing for KuickPay's "Hybrid" voucher API (Insert Voucher, Bill
    # Payment Bulk Inquiry): JSON POSTs authenticated by `username`/`password`
    # headers, unlike the hosted checkout's Basic Auth. Never logs the request
    # body (it carries the candidate's name and mobile number) or the credential
    # headers -- only the step, the URL and the response.
    class KuickpayHybridHttpClient
      def initialize(configuration:)
        @configuration = configuration
      end

      def post(path:, payload:, step:)
        uri = URI.join(@configuration.kuickpay_hybrid_base_url, path)
        response = http_response_for(uri, build_request(uri, payload))
        log_call(step:, uri:, response:)
        response
      end

      private

      def build_request(uri, payload)
        request = Net::HTTP::Post.new(uri)
        request['username'] = @configuration.kuickpay_hybrid_username
        request['password'] = @configuration.kuickpay_hybrid_password
        request.content_type = 'application/json'
        request.body = payload.to_json
        request
      end

      def http_response_for(uri, request)
        Net::HTTP.start(
          uri.host, uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: @configuration.kuickpay_open_timeout,
          read_timeout: @configuration.kuickpay_read_timeout
        ) { |http| http.request(request) }
      end

      def log_call(step:, uri:, response:)
        body = response.body.to_s.truncate(500)
        Rails.logger.info("[KuickPay][#{step}] url=#{uri} status=#{response.code} body=#{body}")
      end
    end
  end
end

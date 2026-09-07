# frozen_string_literal: true

require 'net/http'

module Sms
  module Providers
    # Real SMS delivery via send.pk (https://sendpk.com/api.php). Application
    # code never touches this class directly -- see Sms::SendMessage, which
    # selects it (or Sms::Providers::TestProvider) by SMS_PROVIDER, per
    # AGENTS.md's "application code must not directly depend on SendPK ...
    # or other vendor-specific APIs."
    #
    # send.pk's "Send Single Message" endpoint (confirmed against send.pk's
    # own published Postman collection, not guessed) is a single plain HTTP
    # endpoint -- no SDK, no signature/HMAC scheme, `api_key`/`sender`/
    # `mobile`/`message` all as POST form fields -- replying with a bare
    # "OK ID:<message id>" on success or a single-digit error code on
    # failure. It also supports a `format=json`/`format=xml` response mode,
    # but its exact field names aren't published anywhere, so this adapter
    # deliberately omits `format` and relies only on the default plain-text
    # contract that *is* fully documented, rather than guessing at an
    # unconfirmed JSON shape.
    class SendpkProvider
      ENDPOINT_PATH = '/api/sms.php'
      # Matches send.pk's own reference PHP snippet, in case their backend
      # is sensitive to it (some low-traffic gateways reject bare/blank
      # user agents as bot traffic).
      USER_AGENT = 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1)'
      # Every failure mode send.pk's docs actually document, by the bare
      # numeric code their API returns for it.
      ERROR_CODES = {
        '1' => 'invalid_api_key',
        '2' => 'missing_api_key',
        '4' => 'missing_sender_id',
        '5' => 'missing_recipient',
        '6' => 'missing_message',
        '7' => 'invalid_recipient',
        '8' => 'insufficient_credit'
      }.freeze
      SUCCESS_PATTERN = /\AOK\s*ID:\s*(?<message_id>\S+)/i

      def initialize(configuration: Configuration.new)
        @configuration = configuration
      end

      def deliver(to:, body:)
        return DeliveryResult.new(success: false, error_code: 'not_configured') unless configured?
        return DeliveryResult.new(success: false, error_code: 'insecure_endpoint_rejected') unless secure_endpoint?

        response = perform_request(to:, body:)
        parse_http_response(response)
      rescue Net::OpenTimeout, Net::ReadTimeout
        DeliveryResult.new(success: false, error_code: 'timeout')
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError
        DeliveryResult.new(success: false, error_code: 'network_error')
      end

      private

      # Both must be set for send.pk to accept a request at all -- the
      # sender id specifically has to be pre-approved in send.pk's own
      # dashboard, so a blank value here means setup isn't finished yet
      # rather than a delivery problem worth a network round-trip to learn.
      def configured?
        @configuration.sendpk_api_key.present? && @configuration.sendpk_sender_id.present?
      end

      # SENDPK_BASE_URL is env-configurable (Sms::Configuration), which
      # would otherwise let a misconfiguration silently send the API key,
      # recipient number and OTP/message body over plain HTTP. Only test
      # ever legitimately needs a non-HTTPS base (a local stub/mock
      # endpoint has no real certificate to present).
      def secure_endpoint?
        return true if Rails.env.test?

        URI.join(@configuration.sendpk_base_url, ENDPOINT_PATH).scheme == 'https'
      rescue URI::Error
        false
      end

      def perform_request(to:, body:)
        uri = URI.join(@configuration.sendpk_base_url, ENDPOINT_PATH)
        request = build_request(uri, to:, body:)
        http_response_for(uri, request)
      end

      def build_request(uri, to:, body:)
        request = Net::HTTP::Post.new(uri)
        request['User-Agent'] = USER_AGENT
        request.set_form_data(request_params(to:, body:))
        request
      end

      def http_response_for(uri, request)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: @configuration.sendpk_open_timeout,
          read_timeout: @configuration.sendpk_read_timeout
        ) { |http| http.request(request) }
      end

      def request_params(to:, body:)
        {
          'api_key' => @configuration.sendpk_api_key,
          'sender' => @configuration.sendpk_sender_id,
          'mobile' => to,
          'message' => body
        }
      end

      # Never trusts response *body* content alone -- a non-2xx status (an
      # API gateway error page, a WAF block page, a maintenance response)
      # is never handed to the success/error-code text parser, regardless
      # of what its body happens to contain. `Net::HTTP#request` does not
      # itself follow redirects, so a 3xx here is send.pk's own response,
      # not something already silently followed -- mapped to its own error
      # code for an honest audit trail rather than falling through to
      # "unknown_error".
      def parse_http_response(response)
        case response
        when Net::HTTPSuccess then parse_response(response.body)
        when Net::HTTPRedirection then DeliveryResult.new(success: false, error_code: 'unexpected_redirect')
        else DeliveryResult.new(success: false, error_code: 'http_error')
        end
      end

      def parse_response(raw_body)
        text = raw_body.to_s.strip
        match = SUCCESS_PATTERN.match(text)
        return DeliveryResult.new(success: true, provider_reference: match[:message_id]) if match

        DeliveryResult.new(success: false, error_code: ERROR_CODES.fetch(text, 'unknown_error'))
      end
    end
  end
end

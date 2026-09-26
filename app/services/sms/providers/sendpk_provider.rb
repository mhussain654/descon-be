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
    # This account uses send.pk's Fixed/OTP SMS (short-code, transactional):
    # the wording lives in a template approved in send.pk's dashboard, and
    # each request sends `template_id` plus `message` as a JSON object of the
    # template's variables (e.g. {"code":"123456","minutes":"5"}) -- free text
    # in `message` is rejected. The endpoint is a single plain HTTP
    # endpoint -- no SDK, no signature/HMAC scheme, `api_key`/`sender`/
    # `mobile`/`template_id`/`message` all as GET query parameters (the only
    # method send.pk documents; the URL therefore carries the API key, so it
    # must never be logged, and only https is accepted outside test) -- replying with a bare
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

      # The full text is fixed in the approved template, so the caller's
      # `body:` is intentionally ignored here -- only `variables` are sent.
      def deliver(to:, variables:, locale: 'en', **)
        return DeliveryResult.new(success: false, error_code: 'not_configured') unless configured?
        return DeliveryResult.new(success: false, error_code: 'insecure_endpoint_rejected') unless secure_endpoint?

        response = perform_request(to:, variables:, locale:)
        parse_http_response(response)
      rescue Net::OpenTimeout, Net::ReadTimeout
        DeliveryResult.new(success: false, error_code: 'timeout')
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError
        DeliveryResult.new(success: false, error_code: 'network_error')
      end

      private

      # All three must be set for send.pk to accept a request at all -- the
      # sender and template id both have to be set up/approved in send.pk's
      # own dashboard, so a blank value here means setup isn't finished yet
      # rather than a delivery problem worth a network round-trip to learn.
      def configured?
        @configuration.sendpk_api_key.present? && @configuration.sendpk_sender_id.present? &&
          @configuration.sendpk_template_id.present?
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

      def perform_request(to:, variables:, locale:)
        uri = URI.join(@configuration.sendpk_base_url, ENDPOINT_PATH)
        request = build_request(uri, to:, variables:, locale:)
        http_response_for(uri, request)
      end

      def build_request(uri, to:, variables:, locale:)
        uri = uri.dup
        uri.query = URI.encode_www_form(request_params(to:, variables:, locale:))
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = USER_AGENT
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

      # send.pk's collection documents `type=unicode` as required for any
      # non-Latin script, which the Urdu template is.
      def request_params(to:, variables:, locale:)
        params = base_params(to:, variables:, locale:)
        params['type'] = 'unicode' if locale.to_s == 'ur'
        params
      end

      def base_params(to:, variables:, locale:)
        {
          'api_key' => @configuration.sendpk_api_key,
          'sender' => @configuration.sendpk_sender_id,
          'mobile' => to,
          'template_id' => @configuration.sendpk_template_id(locale),
          'message' => variables.transform_values(&:to_s).to_json
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

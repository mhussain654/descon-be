# frozen_string_literal: true

require 'net/http'

module AiCalls
  module Providers
    # Outgoing Twilio REST calls only -- carrier/telephony status and cost
    # reconciliation via the Call resource, authenticated with HTTP Basic
    # Auth (Account SID + Auth Token). Deliberately NOT used for primary
    # call origination: ElevenLabs originates the outbound call itself on
    # our imported Twilio number (see ElevenLabsAdapter#initiate_outbound_call).
    #
    # Also deliberately separate from TwilioWebhookVerifier: verifying an
    # *inbound* Twilio webhook signature and authenticating our own
    # *outgoing* REST calls are two unrelated mechanisms (HMAC-SHA1 request
    # validation vs. Basic Auth), and conflating them in one class was an
    # early mistake in this feature's design -- see the implementation plan.
    class TwilioAdapter
      def initialize(configuration: AiCalls::Configuration.new)
        @configuration = configuration
      end

      def fetch_call(call_sid:)
        perform_request("/2010-04-01/Accounts/#{@configuration.twilio_account_sid}/Calls/#{call_sid}.json")
      end

      def fetch_call_cost(call_sid:)
        call = fetch_call(call_sid:)
        { price: call['price'], price_unit: call['price_unit'] }
      end

      def available? = @configuration.twilio_account_sid.present? && @configuration.twilio_auth_token.present?

      private

      def perform_request(path)
        raise AiCallProviderUnavailableError unless available?

        uri = URI.join(@configuration.twilio_base_url, path)
        response = http_response_for(uri, build_request(uri))
        parse_response(response)
      rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error
        raise AiCallProviderRequestError
      end

      def build_request(uri)
        request = Net::HTTP::Get.new(uri)
        request.basic_auth(@configuration.twilio_account_sid, @configuration.twilio_auth_token)
        request
      end

      def http_response_for(uri, request)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: @configuration.twilio_open_timeout,
          read_timeout: @configuration.twilio_read_timeout
        ) { |http| http.request(request) }
      end

      def parse_response(response)
        body = response.body.to_s.presence ? JSON.parse(response.body) : {}
        return body if response.is_a?(Net::HTTPSuccess)

        raise AiCallProviderRequestError
      end
    end
  end
end

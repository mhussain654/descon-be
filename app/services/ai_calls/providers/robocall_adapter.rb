# frozen_string_literal: true

require 'net/http'

module AiCalls
  module Providers
    # Isolates the RoboCall.pk voice API behind one adapter (AGENTS.md:
    # "application code must not directly depend on ... vendor-specific
    # APIs"), using the same plain Net::HTTP pattern as ElevenlabsAdapter.
    #
    # RoboCall plays a fixed, pre-recorded voice (`voice_id`) to a number and
    # has no webhooks: the result is read by polling #fetch_call. Every
    # endpoint is a GET with the api key in the query string, so this class
    # never logs a URL and never puts a provider message or URL into an error
    # (raised errors carry only our own fixed, localized text).
    class RobocallAdapter
      CALLS_PATH = '/api/calls'
      # RoboCall's own spelling of the multiple-calls endpoint.
      MULTIPLE_CALLS_PATH = '/api/mutliple_calls'
      CALL_STATUS_PATH = '/api/get_call'
      VERIFY_KEY_PATH = '/api/verify-key'
      BALANCE_PATH = '/api/check_balance'

      CallResult = Struct.new(:call_id, keyword_init: true)
      # `status_code` is RoboCall's numeric call status (nil if unreadable);
      # `dtmf` is the key the candidate pressed, if any.
      CallStatus = Struct.new(:status_code, :dtmf, keyword_init: true)

      def initialize(configuration: AiCalls::RobocallConfiguration.new)
        @configuration = configuration
      end

      def available? = @configuration.api_key.present?

      # Places one call. RoboCall names the destination number `caller_id`,
      # in international format without the plus sign (923001234567).
      #
      # Raises only when RoboCall did not accept the call. An accepted call whose
      # response carries no usable id comes back with a nil `call_id`: the call
      # WAS placed, so the caller must not treat that as a failure and retry.
      def initiate_call(voice_id:, to_number:)
        body = perform_request(CALLS_PATH, caller_id: digits_only(to_number), voice_id:)
        raise AiCallProviderRequestError if body.key?('status') && body['status'].to_i != 200

        CallResult.new(call_id: provider_call_id(body))
      end

      # Places one call per number with a single request and returns RoboCall's
      # parsed response untouched: the shape of its answer for several numbers
      # is not documented, so it is only used by `ai_calls:robocall:multiple`
      # to look at the real response before anything depends on it.
      def initiate_multiple_calls_raw(voice_id:, to_numbers:)
        caller_id = Array(to_numbers).map { |number| digits_only(number) }.join(',')
        perform_request(MULTIPLE_CALLS_PATH, caller_id:, voice_id:)
      end

      def fetch_call(call_id:)
        data = perform_request(CALL_STATUS_PATH, call_id:)['data']
        data = {} unless data.is_a?(Hash)
        CallStatus.new(status_code: Integer(data['call_status'], exception: false),
                       dtmf: data['dtmf'].to_s.strip.presence)
      end

      # Used by `rake ai_calls:robocall_check`: whether the key is accepted and
      # what balance is left. Returns the parsed responses.
      def verify_key = perform_request(VERIFY_KEY_PATH)

      def check_balance = perform_request(BALANCE_PATH)

      private

      def digits_only(number) = number.to_s.delete('^0-9')

      # RoboCall's own docs disagree on the name: `call_id` in the written
      # reference, `order_id` in the sample response shown in the portal.
      def provider_call_id(body)
        data = body['data'].is_a?(Hash) ? body['data'] : {}
        (data['call_id'].presence || data['order_id'].presence).to_s.presence
      end

      def perform_request(path, **params)
        raise AiCallProviderUnavailableError unless available?

        uri = URI.join(@configuration.base_url, path)
        uri.query = URI.encode_www_form(params.merge(api_key: @configuration.api_key))
        parse_response(http_response_for(uri))
      rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
        raise AiCallProviderRequestError
      end

      def http_response_for(uri)
        Net::HTTP.start(
          uri.host, uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: @configuration.open_timeout,
          read_timeout: @configuration.read_timeout
        ) { |http| http.request(Net::HTTP::Get.new(uri)) }
      end

      def parse_response(response)
        raise AiCallProviderRequestError unless response.is_a?(Net::HTTPSuccess)

        body = response.body.to_s.presence ? JSON.parse(response.body) : {}
        body.is_a?(Hash) ? body : raise(AiCallProviderRequestError)
      end
    end
  end
end

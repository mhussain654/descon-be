# frozen_string_literal: true

require 'net/http'

module AiCalls
  module Providers
    # Isolates the ElevenLabs Conversational AI dependency behind one
    # adapter (AGENTS.md: "application code must not directly depend on
    # ... vendor-specific APIs"), mirroring
    # Payments::Providers::KuickpayHostedCheckoutAdapter's plain
    # Net::HTTP + OpenSSL isolation pattern rather than pulling in a vendor
    # SDK gem for a handful of endpoints.
    #
    # ElevenLabs originates the Twilio call leg itself for outbound calls
    # (via #initiate_outbound_call) -- this adapter never talks to the
    # Twilio API directly; see AiCalls::Providers::TwilioAdapter for that.
    class ElevenlabsAdapter
      OUTBOUND_CALL_PATH = '/v1/convai/twilio/outbound-call'
      SIGNATURE_HEADER_PATTERN = /\At=(?<timestamp>\d+),v0=(?<signature>[0-9a-f]+)\z/i
      SIGNATURE_TOLERANCE = 30.minutes

      def initialize(configuration: AiCalls::Configuration.new)
        @configuration = configuration
      end

      # Originates an outbound call. `request.dynamic_variables`/
      # `request.conversation_config_override` are the already-assembled
      # per-call content (candidate name, scenario prompt override, etc.) --
      # building that content is the caller's job
      # (AiCalls::TriggerOutboundCallService), this method only knows the
      # wire format ElevenLabs expects.
      def initiate_outbound_call(request)
        response = perform_request(:post, OUTBOUND_CALL_PATH, outbound_call_payload(request))
        OutboundCallResult.new(
          conversation_id: response['conversation_id'],
          twilio_call_sid: response['callSid'] || response['call_sid']
        )
      end

      # Used by the reconciliation job -- returns the raw parsed response so
      # the caller can read whichever fields (status, analysis, metadata)
      # it needs without this adapter guessing at a fixed shape.
      def fetch_conversation(conversation_id:)
        perform_request(:get, "/v1/convai/conversations/#{conversation_id}")
      end

      def fetch_agent_config(agent_id:)
        perform_request(:get, "/v1/convai/agents/#{agent_id}")
      end

      def update_agent_config(agent_id:, config:)
        perform_request(:patch, "/v1/convai/agents/#{agent_id}", config)
      end

      # Verifies the `ElevenLabs-Signature: t=<unix>,v0=<hex>` header --
      # HMAC-SHA256 over "#{timestamp}.#{raw_body}", constant-time compared,
      # with a bounded replay-tolerance window. Hard-fails (raises) on any
      # verification failure -- this is the sole channel for call-outcome
      # truth, so it must never soft-fail (AGENTS.md: "Verify signatures and
      # authenticity of inbound webhooks").
      def verify_webhook_signature!(header:, raw_body:)
        raise AiCallSignatureInvalidError unless webhook_signature_valid?(header:, raw_body:)
      end

      def available? = @configuration.elevenlabs_api_key.present?

      private

      def outbound_call_payload(request)
        {
          agent_id: request.agent_id,
          agent_phone_number_id: request.agent_phone_number_id,
          to_number: request.to_number,
          call_recording_enabled: request.recording_enabled,
          conversation_initiation_client_data: {
            dynamic_variables: request.dynamic_variables,
            conversation_config_override: request.conversation_config_override
          }
        }
      end

      def webhook_signature_valid?(header:, raw_body:)
        parsed = parse_signature_header(header)
        return false unless parsed
        return false if signature_expired?(parsed.fetch(:timestamp))

        expected = compute_signature(timestamp: parsed.fetch(:timestamp), raw_body:)
        secure_compare(parsed.fetch(:signature), expected)
      end

      def parse_signature_header(header)
        match = SIGNATURE_HEADER_PATTERN.match(header.to_s)
        return nil unless match

        { timestamp: match[:timestamp], signature: match[:signature].downcase }
      end

      def signature_expired?(timestamp)
        signed_at = Time.zone.at(timestamp.to_i)
        (Time.current - signed_at).abs > SIGNATURE_TOLERANCE
      rescue ArgumentError, TypeError
        true
      end

      def compute_signature(timestamp:, raw_body:)
        secret = @configuration.elevenlabs_webhook_signing_secret.to_s
        OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{raw_body}")
      end

      def secure_compare(provided, expected)
        provided.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      def perform_request(method, path, body = nil)
        raise AiCallProviderUnavailableError unless available?

        uri = URI.join(@configuration.elevenlabs_base_url, path)
        response = http_response_for(uri, build_request(method, uri, body))
        parse_response(response)
      rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error
        raise AiCallProviderRequestError
      end

      def build_request(method, uri, body)
        request = request_class(method).new(uri)
        request['xi-api-key'] = @configuration.elevenlabs_api_key
        request.content_type = 'application/json'
        request.body = body.to_json if body
        request
      end

      def request_class(method)
        { post: Net::HTTP::Post, get: Net::HTTP::Get, patch: Net::HTTP::Patch }.fetch(method)
      end

      def http_response_for(uri, request)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: @configuration.elevenlabs_open_timeout,
          read_timeout: @configuration.elevenlabs_read_timeout
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

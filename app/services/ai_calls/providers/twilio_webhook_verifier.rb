# frozen_string_literal: true

module AiCalls
  module Providers
    # Verifies the `X-Twilio-Signature` header Twilio sends on inbound
    # status-callback webhooks: HMAC-SHA1 over the full callback URL with
    # every POST param's key+value concatenated in sorted-key order,
    # base64-encoded (Twilio's own documented algorithm). Hand-rolled with
    # stdlib rather than the `twilio-ruby` gem, matching this codebase's
    # established preference for plain Net::HTTP/OpenSSL provider adapters
    # over vendor SDKs (see Payments::Providers::KuickpayHostedCheckoutAdapter).
    #
    # Deliberately separate from TwilioAdapter: this verifies signatures on
    # *inbound* requests to us; TwilioAdapter authenticates *outgoing*
    # requests we make to Twilio's API. Different mechanisms, different
    # classes -- conflating them was an early mistake in this feature's
    # design (see the implementation plan).
    class TwilioWebhookVerifier
      def initialize(configuration: AiCalls::Configuration.new)
        @configuration = configuration
      end

      def verify!(signature:, url:, params:)
        raise AiCallSignatureInvalidError unless valid?(signature:, url:, params:)
      end

      def valid?(signature:, url:, params:)
        return false if @configuration.twilio_auth_token.blank? || signature.blank?

        secure_compare(signature, compute_signature(url:, params:))
      end

      private

      def compute_signature(url:, params:)
        digest = OpenSSL::HMAC.digest('SHA1', @configuration.twilio_auth_token, url + sorted_param_string(params))
        Base64.strict_encode64(digest)
      end

      def sorted_param_string(params)
        params.to_h.sort.map { |key, value| "#{key}#{value}" }.join
      end

      def secure_compare(provided, expected)
        provided.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end
    end
  end
end

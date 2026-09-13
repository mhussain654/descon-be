# frozen_string_literal: true

module AiCalls
  module Tools
    # Maps a tool_name to its handler class, mirroring
    # Payments::ProviderRegistry's shape -- the one place that knows which
    # class backs which ElevenLabs tool. Every handler shares one call
    # signature: `.call(candidate_ai_call:, params:)`.
    class Registry
      HANDLERS_BY_TOOL_NAME = {
        'verify_caller_identity' => VerifyCallerIdentity,
        'get_application_status' => GetApplicationStatus,
        'get_missing_documents' => GetMissingDocuments,
        'get_payment_status' => GetPaymentStatus,
        'get_qvc_status' => GetQvcStatus,
        'get_visa_status' => GetVisaStatus,
        'get_protection_status' => GetProtectionStatus,
        'get_flight_information' => GetFlightInformation,
        'create_callback_request' => CreateCallbackRequest,
        'transfer_to_human' => TransferToHuman
      }.freeze

      # Tools reachable before verification succeeds -- everything else
      # requires `verification_status` to already reflect success (checked
      # independently by VerifiedDataTool for the 7 data-retrieval tools;
      # these three don't subclass it because they either perform
      # verification itself or never disclose candidate-specific data).
      PRE_VERIFICATION_TOOLS = %w[verify_caller_identity create_callback_request transfer_to_human].freeze

      def self.fetch(tool_name)
        HANDLERS_BY_TOOL_NAME.fetch(tool_name.to_s) do
          raise ArgumentError, "Unknown AI call tool: #{tool_name.inspect}"
        end
      end
    end
  end
end

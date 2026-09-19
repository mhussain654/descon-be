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
        'create_callback_request' => CreateCallbackRequest
      }.freeze

      # Tools reachable before verification succeeds -- everything else
      # requires `verification_status` to already reflect success (checked
      # independently by VerifiedDataTool for the 7 data-retrieval tools;
      # these two don't subclass it because they either perform
      # verification itself or never disclose candidate-specific data).
      #
      # Live transfer to a human is handled entirely by ElevenLabs' own
      # transfer_to_number system tool (see AiCalls::AgentConfigs::Baseline)
      # once configured -- it runs inside ElevenLabs' own conversational
      # engine and never calls this dispatcher, so there is no
      # `transfer_to_human` custom tool here to route to (removed 2026-09-16;
      # it was a deliberate callback-only placeholder for exactly this
      # capability, blocked on Trello MPS-709).
      PRE_VERIFICATION_TOOLS = %w[verify_caller_identity create_callback_request].freeze

      # The 7 data-retrieval tools -- pure reads with no side effect to
      # protect via replay-cached idempotency (see
      # AiCalls::ClaimToolCallEventService).
      READ_ONLY_TOOL_NAMES = (HANDLERS_BY_TOOL_NAME.keys - PRE_VERIFICATION_TOOLS).freeze

      def self.fetch(tool_name)
        HANDLERS_BY_TOOL_NAME.fetch(tool_name.to_s) do
          raise ArgumentError, "Unknown AI call tool: #{tool_name.inspect}"
        end
      end

      def self.read_only_tool_names = READ_ONLY_TOOL_NAMES
    end
  end
end

# frozen_string_literal: true

module AiCalls
  module Prompts
    # Maps a `call_reason` code to its ScenarioPrompt class, mirroring
    # Payments::ProviderRegistry's shape -- the one place that knows which
    # prompt class backs which admin-triggered call reason.
    class ScenarioPromptRegistry
      PROMPTS_BY_CALL_REASON = {
        'missing_documents' => MissingDocumentsPrompt,
        'protection_appearance_reminder' => ProtectionAppearanceReminderPrompt,
        'urgent_compliance_action' => UrgentComplianceActionPrompt,
        'flight_information' => FlightInformationPrompt
      }.freeze

      def self.fetch(call_reason)
        PROMPTS_BY_CALL_REASON.fetch(call_reason.to_s) do
          raise ArgumentError, "Unknown outbound AI call reason: #{call_reason.inspect}"
        end
      end
    end
  end
end

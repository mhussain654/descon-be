# frozen_string_literal: true

module AiCalls
  module Prompts
    # Base for the 4 admin-triggered outbound call-reason prompts. Each call
    # is a real two-way conversation with full tool access (per the client's
    # "candidate can ask anything about his application" clarification), not
    # a scripted announcement -- this class only sets the *opening topic*
    # that layers on top of the repo-committed permanent baseline
    # (AiCalls::AgentConfigs::Baseline), via ElevenLabs' `first_message`/
    # `dynamic_variables` call-time override. It never carries guardrail or
    # tool-use instructions -- those live only in the baseline.
    #
    # PLACEHOLDER: `opening_line` content is not yet client-approved wording
    # (see config/locales/api.en.yml/api.ur.yml) -- do not trigger a real call
    # against this content in production.
    class ScenarioPrompt
      def self.call_reason
        raise NotImplementedError
      end

      def self.build(candidate:, language_code:)
        new(candidate:, language_code:).build
      end

      def initialize(candidate:, language_code:)
        @candidate = candidate
        @language_code = language_code
      end

      def build
        OutboundPromptContent.new(dynamic_variables:, conversation_config_override:)
      end

      private

      attr_reader :candidate, :language_code

      def dynamic_variables
        { 'candidate_name' => candidate.full_name, 'call_reason' => self.class.call_reason }
      end

      def conversation_config_override
        { 'agent' => { 'first_message' => opening_line, 'language' => language_code } }
      end

      def opening_line
        I18n.t("api.ai_calls.prompts.#{self.class.call_reason}.opening_line", locale: language_code.to_sym)
      end
    end
  end
end

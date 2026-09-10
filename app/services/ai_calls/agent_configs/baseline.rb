# frozen_string_literal: true

module AiCalls
  module AgentConfigs
    # The repo-committed, PR-reviewed canonical configuration for one
    # ElevenLabs conversational agent role (outbound or inbound). This is
    # what AiCalls::AgentConfigSync pushes (`sync!`) and compares the
    # currently-published agent against (`check`) -- the permanent baseline
    # prompt (identity, guardrails, tool-use rules) must never silently
    # drift from this reviewed version.
    #
    # PLACEHOLDER_MARKER: the prompt text is currently a placeholder, not
    # client-approved guardrail content (see config/locales/api.en.yml).
    # AiCalls::AgentConfigSync hard-refuses to sync a placeholder baseline
    # into production, confirmation flag notwithstanding.
    class Baseline
      PLACEHOLDER_MARKER = '[PLACEHOLDER'
      ROLES = %w[outbound inbound].freeze

      # Only these top-level agent-config keys are managed by the baseline --
      # drift comparisons are scoped to exactly what we push, not the full
      # provider response (which also echoes back read-only/provider-owned
      # fields we don't control).
      MANAGED_KEYS = %w[name conversation_config].freeze

      def self.for(role)
        role_name = role.to_s
        raise ArgumentError, "unknown AI call agent role: #{role.inspect}" unless ROLES.include?(role_name)

        new(role_name)
      end

      attr_reader :role

      def initialize(role)
        @role = role
      end

      def agent_id(configuration: AiCalls::Configuration.new)
        configuration.public_send(:"elevenlabs_#{role}_agent_id")
      end

      def config
        {
          'name' => "Descon #{role.capitalize} AI Call Agent",
          'conversation_config' => {
            'agent' => { 'language' => 'en', 'prompt' => { 'prompt' => prompt_text } }
          }
        }
      end

      def digest
        Digest::SHA256.hexdigest(normalized_json(config))
      end

      def digest_for_remote(remote_config)
        Digest::SHA256.hexdigest(normalized_json(remote_config.to_h.slice(*MANAGED_KEYS)))
      end

      def placeholder? = prompt_text.include?(PLACEHOLDER_MARKER)

      private

      def prompt_text
        I18n.t("api.ai_calls.prompts.#{role}.baseline", locale: :en)
      end

      def normalized_json(value)
        JSON.generate(deep_sort(value))
      end

      def deep_sort(value)
        case value
        when Hash
          value.sort.to_h { |key, nested| [key, deep_sort(nested)] }
        when Array
          value.map { |nested| deep_sort(nested) }
        else
          value
        end
      end
    end
  end
end

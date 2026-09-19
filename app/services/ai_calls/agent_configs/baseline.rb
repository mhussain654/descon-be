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
    #
    # The transfer_to_number built-in tool (ElevenLabs' own live human-
    # handoff mechanism, confirmed 2026-09-15 to work exactly this way for
    # a natively-imported Twilio number, which is how this app's calls are
    # already originated) is included only once an admin has actually set
    # AiCallOperationalSetting#human_transfer_phone_number and
    # AI_VOICE_HUMAN_TRANSFER_ENABLED is on -- see #with_built_in_tools.
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

      def config(configuration: AiCalls::Configuration.new)
        {
          'name' => "Descon #{role.capitalize} AI Call Agent",
          'conversation_config' => { 'agent' => agent_config(configuration:) }
        }
      end

      def digest(configuration: AiCalls::Configuration.new)
        Digest::SHA256.hexdigest(normalized_json(config(configuration:)))
      end

      def digest_for_remote(remote_config)
        Digest::SHA256.hexdigest(normalized_json(remote_config.to_h.slice(*MANAGED_KEYS)))
      end

      def placeholder? = prompt_text.include?(PLACEHOLDER_MARKER)

      private

      # Inbound has no per-call trigger service to layer a `first_message`
      # override onto (unlike outbound, whose ScenarioPrompt/
      # WorkflowStageAnnouncementPrompt set it per call) -- the greeting
      # that answers every inbound call has to live on the baseline itself.
      def agent_config(configuration:)
        base = { 'language' => 'en', 'prompt' => { 'prompt' => prompt_text } }
        base = base.merge('first_message' => opening_line_text) if role == 'inbound'
        with_built_in_tools(base, configuration:)
      end

      # Omits the transfer_to_number system tool entirely -- rather than
      # including it with a blank/placeholder destination -- until an admin
      # has actually set AiCallOperationalSetting#human_transfer_phone_number
      # and the human_transfer_enabled? flag is on. This is the only way to
      # guarantee a freshly-provisioned environment can never push a fake or
      # missing destination into a live agent that would really dial it.
      def with_built_in_tools(base, configuration:)
        return base unless configuration.human_transfer_enabled? && configuration.human_transfer_phone_number.present?

        prompt = base.fetch('prompt').merge('built_in_tools' => transfer_to_number_tool(configuration))
        base.merge('prompt' => prompt)
      end

      def transfer_to_number_tool(configuration)
        {
          'transfer_to_number' => {
            'type' => 'system',
            'name' => 'transfer_to_number',
            'params' => { 'system_tool_type' => 'transfer_to_number', 'transfers' => [transfer_rule(configuration)] }
          }
        }
      end

      def transfer_rule(configuration)
        {
          'transfer_destination' => { 'type' => 'phone', 'phone_number' => configuration.human_transfer_phone_number },
          'condition' => 'The candidate explicitly asks to speak with a human agent.',
          'transfer_type' => 'conference'
        }
      end

      def prompt_text
        I18n.t("api.ai_calls.prompts.#{role}.baseline", locale: :en)
      end

      def opening_line_text
        I18n.t('api.ai_calls.prompts.inbound.opening_line', locale: :en)
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

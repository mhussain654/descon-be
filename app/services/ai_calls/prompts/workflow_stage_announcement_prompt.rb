# frozen_string_literal: true

module AiCalls
  module Prompts
    # Wraps one WorkflowStageCallScript's admin-editable announcement text
    # into the same OutboundPromptContent shape ScenarioPrompt subclasses
    # produce, so TriggerOutboundCallService doesn't need to know which of
    # the two flows it's serving. Unlike ScenarioPrompt, this is built from
    # an instance (the announcement text is per-row, not a fixed constant
    # per class) -- carries no guardrail/tool-use content, only the opening
    # line (see AiCalls::OutboundCallPlan and the plan's DB-editable-content
    # boundary rule).
    #
    # Selects `announcement_en`/`announcement_ur` by the candidate's own
    # `language_code` at call time, mirroring ScenarioPrompt#opening_line's
    # identical per-candidate locale selection -- falls back to
    # `announcement_en` if the requested locale's text is blank (a stage
    # whose Urdu wording isn't ready yet still places a real call, in
    # English, rather than none at all).
    class WorkflowStageAnnouncementPrompt
      def initialize(announcement_en:, announcement_ur:)
        @announcement_en = announcement_en
        @announcement_ur = announcement_ur
      end

      def build(candidate:, language_code:)
        OutboundPromptContent.new(
          dynamic_variables: dynamic_variables(candidate),
          conversation_config_override: conversation_config_override(language_code)
        )
      end

      private

      def dynamic_variables(candidate)
        { 'candidate_name' => candidate.full_name, 'call_reason' => 'workflow_stage_notification' }
      end

      def conversation_config_override(language_code)
        { 'agent' => { 'first_message' => announcement_for(language_code), 'language' => language_code } }
      end

      def announcement_for(language_code)
        return @announcement_ur if language_code.to_s == 'ur' && @announcement_ur.present?

        @announcement_en
      end
    end
  end
end

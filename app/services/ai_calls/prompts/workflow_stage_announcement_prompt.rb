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
    class WorkflowStageAnnouncementPrompt
      def initialize(announcement:)
        @announcement = announcement
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
        { 'agent' => { 'first_message' => @announcement, 'language' => language_code } }
      end
    end
  end
end

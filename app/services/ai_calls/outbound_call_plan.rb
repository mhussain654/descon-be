# frozen_string_literal: true

module AiCalls
  # Describes what one outbound call should say (`prompt_source`, something
  # responding to `#build(candidate:, language_code:)`) and how it should be
  # recorded (`call_reason`, `workflow_stage_code`) -- the one thing
  # TriggerOutboundCallService needs to stay shared between the
  # admin-triggered (4 fixed scenarios) and workflow-stage-triggered flows,
  # rather than duplicating its trigger/guard/creation mechanics per flow.
  OutboundCallPlan = Struct.new(:call_reason, :prompt_source, :workflow_stage_code, keyword_init: true) do
    def self.for_admin_scenario(call_reason)
      new(
        call_reason: call_reason.to_s,
        prompt_source: Prompts::ScenarioPromptRegistry.fetch(call_reason),
        workflow_stage_code: nil
      )
    end

    def self.for_workflow_stage(script)
      new(
        call_reason: 'workflow_stage_notification',
        prompt_source: Prompts::WorkflowStageAnnouncementPrompt.new(announcement: script.announcement),
        workflow_stage_code: script.workflow_stage_code
      )
    end
  end
end

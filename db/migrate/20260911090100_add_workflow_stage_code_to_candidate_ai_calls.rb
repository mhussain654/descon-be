# frozen_string_literal: true

# Set only when call_reason == 'workflow_stage_notification' -- the
# destination WorkflowStage.code that triggered the call (see the plan's
# "Client clarifications" #6 and AiCalls::TriggerWorkflowStageCallService).
class AddWorkflowStageCodeToCandidateAiCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :candidate_ai_calls, :workflow_stage_code, :string
    add_check_constraint :candidate_ai_calls, "workflow_stage_code IS NULL OR workflow_stage_code ~ '^[a-z0-9_]+$'",
                         name: 'candidate_ai_calls_workflow_stage_code_format'
    add_index :candidate_ai_calls, %i[candidate_assignment_id workflow_stage_code],
              name: 'index_candidate_ai_calls_on_assignment_and_workflow_stage'
  end
end

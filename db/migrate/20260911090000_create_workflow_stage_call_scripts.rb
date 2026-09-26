# frozen_string_literal: true

# The only DB-editable content in the AI voice calling feature (see the
# plan's "Client clarifications" #5/#6): the per-workflow-stage opening
# announcement line for automatically-triggered calls. `workflow_stage_code`
# is validated at the model level against WorkflowStage::CANONICAL_STAGES --
# a fixed, code-level list -- so this table's row set never grows beyond one
# row per canonical stage; there is no admin path to add a stage here.
class CreateWorkflowStageCallScripts < ActiveRecord::Migration[8.1]
  def change
    create_workflow_stage_call_scripts_table
    add_workflow_stage_call_script_constraints
  end

  private

  def create_workflow_stage_call_scripts_table
    create_table :workflow_stage_call_scripts do |t|
      t.string :workflow_stage_code, null: false
      t.text :announcement, null: false
      t.boolean :active, null: false, default: false
      t.string :language_code, null: false, default: 'en'
      t.references :updated_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :workflow_stage_call_scripts, :workflow_stage_code, unique: true
  end

  def add_workflow_stage_call_script_constraints
    add_check_constraint :workflow_stage_call_scripts, "workflow_stage_code ~ '^[a-z0-9_]+$'",
                         name: 'workflow_stage_call_scripts_stage_code_format'
    add_check_constraint :workflow_stage_call_scripts, "language_code IN ('en', 'ur')",
                         name: 'workflow_stage_call_scripts_language_code'
  end
end

# frozen_string_literal: true

# Fixes a real language mismatch: WorkflowStageAnnouncementPrompt always
# told ElevenLabs to speak in the *candidate's* preferred_locale, but each
# script only ever stored one language's text -- so a candidate whose
# locale didn't match the script's `language_code` would hear the agent
# announce itself in the right language while reading the wrong one's
# text. Mirrors AiCalls::Prompts::ScenarioPrompt's existing, correct
# pattern (an English and an Urdu opening_line, selected per candidate at
# call time) instead of a single language_code tag.
class AddBilingualAnnouncementsToWorkflowStageCallScripts < ActiveRecord::Migration[8.1]
  def change
    rename_column :workflow_stage_call_scripts, :announcement, :announcement_en
    add_column :workflow_stage_call_scripts, :announcement_ur, :text

    remove_check_constraint :workflow_stage_call_scripts, name: 'workflow_stage_call_scripts_language_code'
    remove_column :workflow_stage_call_scripts, :language_code, :string, null: false, default: 'en'
  end
end

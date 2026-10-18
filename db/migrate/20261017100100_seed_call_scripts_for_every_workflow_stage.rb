# frozen_string_literal: true

# Admins can only edit an existing workflow_stage_call_scripts row (there is no
# create route), and only six stages were seeded. With RoboCall a call is just a
# voice per stage, so give every stage a row -- inactive, with no voice (no call
# is placed until an admin sets one and activates it). Rows that exist are left
# untouched. On a fresh database workflow_stages is still empty here; db:seed
# then creates the same rows.
class SeedCallScriptsForEveryWorkflowStage < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      INSERT INTO workflow_stage_call_scripts (workflow_stage_code, active, created_at, updated_at)
      SELECT ws.code, FALSE, NOW(), NOW()
      FROM workflow_stages ws
      WHERE NOT EXISTS (
        SELECT 1 FROM workflow_stage_call_scripts s WHERE s.workflow_stage_code = ws.code
      )
    SQL
  end

  def down
    execute <<~SQL.squish
      DELETE FROM workflow_stage_call_scripts
      WHERE active = FALSE AND voice_id IS NULL AND announcement_en IS NULL AND announcement_ur IS NULL
    SQL
  end
end

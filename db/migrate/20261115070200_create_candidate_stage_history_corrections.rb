# frozen_string_literal: true

# Corrected values for a stage move's details, set later by a developer (e.g. a
# medical appointment's centre or date). Stage history itself is append-only,
# so the corrected values live here, one row per history entry, and are laid
# over the original details when the history is read. Each change is also an
# audit event holding the old and new values and the reason.
class CreateCandidateStageHistoryCorrections < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_stage_history_corrections do |t|
      t.references :candidate_stage_history, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :details, null: false, default: {}
      t.references :updated_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end

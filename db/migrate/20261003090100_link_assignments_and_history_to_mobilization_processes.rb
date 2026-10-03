# frozen_string_literal: true

# Ties every candidate assignment to the process version it was created
# under (resolved once, never re-resolved, for auditability) and to its
# current stage within that process -- both required.
#
# Every stage-history row records the process and the process stage it moved
# into (required) and the one it left (absent only for an assignment's first
# entry), plus an immutable snapshot of both ends -- code, English/Urdu name
# and position as they read at transition time. History is served from that
# snapshot, so it never changes when the catalog's labels or a later process
# version change.
class LinkAssignmentsAndHistoryToMobilizationProcesses < ActiveRecord::Migration[8.1]
  # (Plain add_reference calls: `null: false` on references is dropped inside
  # a bulk change_table.) NOT NULL without defaults is safe: the database is
  # reset and reseeded, never migrated with existing rows.
  # rubocop:disable Metrics/MethodLength, Rails/NotNullColumn
  def change
    add_reference :candidate_assignments, :mobilization_process, null: false, foreign_key: true
    add_reference :candidate_assignments, :current_mobilization_process_stage,
                  null: false, foreign_key: { to_table: :mobilization_process_stages }

    add_reference :candidate_stage_histories, :mobilization_process, null: false, foreign_key: true
    add_reference :candidate_stage_histories, :from_mobilization_process_stage,
                  foreign_key: { to_table: :mobilization_process_stages }
    add_reference :candidate_stage_histories, :to_mobilization_process_stage,
                  null: false, foreign_key: { to_table: :mobilization_process_stages }
    change_table :candidate_stage_histories, bulk: true do |t|
      t.string :stage_code, null: false
      t.string :stage_name_en, null: false
      t.string :stage_name_ur, null: false
      t.integer :position, null: false
      t.string :from_stage_code
      t.string :from_stage_name_en
      t.string :from_stage_name_ur
      t.integer :from_position
    end
  end
  # rubocop:enable Metrics/MethodLength, Rails/NotNullColumn
end

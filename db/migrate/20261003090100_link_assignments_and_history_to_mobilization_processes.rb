# frozen_string_literal: true

# Ties every candidate assignment to the process version it was created
# under (resolved once, never re-resolved, for auditability) and to its
# current stage within that process. Stage history additionally records the
# process stages a transition moved between plus an immutable snapshot of the
# stage's code, names and position at that moment, so history stays readable
# even after later process versions reorder or rename stages.
#
# Columns are nullable here (existing rows are backfilled by
# `bin/rails mobilization:backfill_processes`); the models require them for
# every new assignment/transition.
class LinkAssignmentsAndHistoryToMobilizationProcesses < ActiveRecord::Migration[8.1]
  # rubocop:disable Metrics/MethodLength
  def change
    change_table :candidate_assignments, bulk: true do |t|
      t.references :mobilization_process, foreign_key: true
      t.references :current_mobilization_process_stage, foreign_key: { to_table: :mobilization_process_stages }
    end

    change_table :candidate_stage_histories, bulk: true do |t|
      t.references :mobilization_process, foreign_key: true
      t.references :from_mobilization_process_stage, foreign_key: { to_table: :mobilization_process_stages }
      t.references :to_mobilization_process_stage, foreign_key: { to_table: :mobilization_process_stages }
      t.string :stage_code
      t.string :stage_name_en
      t.string :stage_name_ur
      t.integer :position
    end
  end
  # rubocop:enable Metrics/MethodLength
end

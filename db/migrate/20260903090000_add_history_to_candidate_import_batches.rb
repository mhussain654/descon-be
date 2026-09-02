# frozen_string_literal: true

class AddHistoryToCandidateImportBatches < ActiveRecord::Migration[8.1]
  def change
    replace_status_constraint
    change_column_default :candidate_import_batches, :status, from: 'preflighted', to: 'queued'
    add_history_columns
    add_index :candidate_import_batches, %i[status created_at]
  end

  private

  def replace_status_constraint
    remove_check_constraint :candidate_import_batches, name: 'candidate_import_batches_status'
    reversible { |direction| migrate_existing_statuses(direction) }
    add_check_constraint :candidate_import_batches,
                         "status IN ('queued', 'processing', 'completed', 'partial', 'failed', 'invalidated')",
                         name: 'candidate_import_batches_status'
  end

  def add_history_columns
    change_table :candidate_import_batches, bulk: true do |table|
      table.datetime :processed_at
      table.datetime :failed_at
      table.string :error_code
      table.integer :skipped_rows, null: false, default: 0
      table.integer :committed_rows, null: false, default: 0
    end
  end

  def migrate_existing_statuses(direction)
    return unless direction.up?

    execute "UPDATE candidate_import_batches SET status = 'queued' WHERE status = 'preflighted'"
    execute "UPDATE candidate_import_batches SET status = 'completed' WHERE status = 'committed'"
  end
end

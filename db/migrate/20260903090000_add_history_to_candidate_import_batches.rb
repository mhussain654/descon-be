# frozen_string_literal: true

class AddHistoryToCandidateImportBatches < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :candidate_import_batches, name: 'candidate_import_batches_status'
    execute "UPDATE candidate_import_batches SET status = 'queued' WHERE status = 'preflighted'"
    execute "UPDATE candidate_import_batches SET status = 'completed' WHERE status = 'committed'"
    add_check_constraint :candidate_import_batches,
                         "status IN ('queued', 'processing', 'completed', 'partial', 'failed', 'invalidated')",
                         name: 'candidate_import_batches_status'
    change_column_default :candidate_import_batches, :status, from: 'preflighted', to: 'queued'
    add_history_columns
    add_index :candidate_import_batches, %i[status created_at]
  end

  def down
    remove_index :candidate_import_batches, %i[status created_at]
    remove_columns :candidate_import_batches, :processed_at, :failed_at, :error_code, :skipped_rows, :committed_rows
    remove_check_constraint :candidate_import_batches, name: 'candidate_import_batches_status'
    restore_legacy_statuses
    change_column_default :candidate_import_batches, :status, from: 'queued', to: 'preflighted'
    add_check_constraint :candidate_import_batches,
                         "status IN ('preflighted', 'committed', 'invalidated')",
                         name: 'candidate_import_batches_status'
  end

  private

  def restore_legacy_statuses
    execute "UPDATE candidate_import_batches SET status = 'preflighted' WHERE status = 'queued'"
    execute "UPDATE candidate_import_batches SET status = 'committed' WHERE status = 'completed'"
    execute <<~SQL.squish
      UPDATE candidate_import_batches SET status = 'invalidated' WHERE status IN ('processing', 'partial', 'failed')
    SQL
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

# frozen_string_literal: true

class CreateCandidateImportRowResults < ActiveRecord::Migration[8.1]
  def change
    create_row_results_table
    add_indexes
    add_constraints
  end

  private

  def create_row_results_table
    create_table :candidate_import_row_results do |table|
      table.references :candidate_import_batch, null: false, foreign_key: true
      table.integer :row_number, null: false
      table.string :status, null: false
      table.string :error_field
      table.string :error_code
      table.timestamps
    end
  end

  def add_indexes
    add_index :candidate_import_row_results, %i[candidate_import_batch_id row_number],
              unique: true, name: 'index_import_row_results_on_batch_and_row'
  end

  def add_constraints
    add_check_constraint :candidate_import_row_results,
                         "status IN ('accepted', 'rejected', 'skipped', 'committed')",
                         name: 'candidate_import_row_results_status'
  end
end

# frozen_string_literal: true

class CreateCandidateImportBatches < ActiveRecord::Migration[8.1]
  def change
    create_batches_table
    add_indexes
    add_constraints
  end

  private

  def create_batches_table
    create_table :candidate_import_batches do |table|
      add_identity_columns(table)
      add_snapshot_columns(table)
      add_count_columns(table)
      add_timestamp_columns(table)
      table.timestamps
    end
  end

  def add_identity_columns(table)
    table.references :actor, null: false, foreign_key: { to_table: :users }
    table.string :public_id, null: false
    table.string :token_digest, null: false
    table.string :status, null: false, default: 'preflighted'
  end

  def add_snapshot_columns(table)
    table.string :source_filename, null: false
    table.string :file_fingerprint, null: false
    table.string :template_version, null: false
    table.string :request_id
    table.text :preflight_payload, null: false
  end

  def add_count_columns(table)
    table.integer :total_rows, null: false, default: 0
    table.integer :accepted_rows, null: false, default: 0
    table.integer :rejected_rows, null: false, default: 0
    table.integer :warning_count, null: false, default: 0
    table.integer :imported_rows, null: false, default: 0
  end

  def add_timestamp_columns(table)
    table.datetime :expires_at, null: false
    table.datetime :committed_at
    table.datetime :invalidated_at
  end

  def add_indexes
    add_index :candidate_import_batches, :public_id, unique: true
    add_index :candidate_import_batches, :token_digest, unique: true
    add_index :candidate_import_batches, :expires_at
  end

  def add_constraints
    add_check_constraint :candidate_import_batches,
                         "status IN ('preflighted', 'committed', 'invalidated')",
                         name: 'candidate_import_batches_status'
  end
end

# frozen_string_literal: true

class CreateCandidateImportBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_import_batches do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.string :token_digest, null: false
      t.string :status, null: false, default: 'preflighted'
      t.string :source_filename, null: false
      t.string :file_fingerprint, null: false
      t.string :template_version, null: false
      t.string :request_id
      t.text :preflight_payload, null: false
      t.integer :total_rows, null: false, default: 0
      t.integer :accepted_rows, null: false, default: 0
      t.integer :rejected_rows, null: false, default: 0
      t.integer :warning_count, null: false, default: 0
      t.integer :imported_rows, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :committed_at
      t.datetime :invalidated_at
      t.timestamps
    end

    add_index :candidate_import_batches, :public_id, unique: true
    add_index :candidate_import_batches, :token_digest, unique: true
    add_index :candidate_import_batches, :expires_at
    add_check_constraint :candidate_import_batches,
                         "status IN ('preflighted', 'committed', 'invalidated')",
                         name: 'candidate_import_batches_status'
  end
end

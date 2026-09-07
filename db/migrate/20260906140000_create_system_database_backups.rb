# frozen_string_literal: true

# Records one attempt (in_progress/succeeded/failed) of the daily database
# backup job (MPS-903). The gzipped pg_dump itself is attached via
# ActiveStorage (see SystemDatabaseBackup#archive) -- this table is the
# admin-visible, permission-gated index of that history, not a duplicate
# of ActiveStorage's own generic blob table.
class CreateSystemDatabaseBackups < ActiveRecord::Migration[8.1]
  def change
    create_table :system_database_backups do |t|
      t.string :public_id, null: false
      t.string :status_code, null: false
      t.datetime :taken_at, null: false
      t.bigint :byte_size
      t.string :checksum_sha256
      t.integer :duration_seconds
      t.text :error_message

      t.timestamps
    end

    add_index :system_database_backups, :public_id, unique: true
    add_index :system_database_backups, :taken_at

    add_check_constraint :system_database_backups,
                         "public_id::text ~ '^[0-9a-f-]{36}$'::text",
                         name: 'system_database_backups_public_id_format'
    add_check_constraint :system_database_backups,
                         "status_code IN ('in_progress', 'succeeded', 'failed')",
                         name: 'system_database_backups_status_code_allowed'
  end
end

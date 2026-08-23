# frozen_string_literal: true

class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_idempotency_keys_table
    add_idempotency_indexes
    add_idempotency_constraints
  end

  private

  def create_idempotency_keys_table
    create_table :idempotency_keys do |t|
      add_request_columns(t)
      add_subject_columns(t)
      add_response_columns(t)
      t.timestamps
    end
  end

  def add_idempotency_indexes
    add_index :idempotency_keys, :expires_at
    add_index :idempotency_keys, %i[subject_type subject_id], name: 'index_idempotency_keys_on_subject'
    execute unique_scope_index_sql
  end

  def add_idempotency_constraints
    check_constraints.each do |name, expression|
      add_check_constraint :idempotency_keys, expression, name:
    end
  end

  def add_request_columns(table)
    table.string :idempotency_scope, null: false
    table.string :key_digest, null: false
    table.string :request_fingerprint, null: false
    table.string :request_method, null: false
    table.string :request_path, null: false
    table.string :status, null: false, default: 'processing'
    table.datetime :expires_at, null: false
  end

  def add_subject_columns(table)
    table.string :subject_type
    table.bigint :subject_id
  end

  def add_response_columns(table)
    table.integer :response_status
    table.jsonb :response_payload
    table.datetime :completed_at
  end

  def unique_scope_index_sql
    <<~SQL.squish
      CREATE UNIQUE INDEX index_idempotency_keys_on_scope_subject_and_key
      ON idempotency_keys (
        idempotency_scope,
        COALESCE(subject_type, '__global__'),
        COALESCE(subject_id, 0),
        key_digest
      )
    SQL
  end

  def check_constraints
    {
      idempotency_keys_status: "status IN ('processing', 'completed')",
      idempotency_keys_request_method_format: "request_method ~ '^[A-Z]+$'",
      idempotency_keys_key_digest_length: 'char_length(key_digest) = 64',
      idempotency_keys_response_consistency: <<~SQL.squish
        (status = 'processing' AND response_status IS NULL AND response_payload IS NULL AND completed_at IS NULL) OR
        (status = 'completed' AND response_status IS NOT NULL AND response_payload IS NOT NULL AND completed_at IS NOT NULL)
      SQL
    }
  end
end

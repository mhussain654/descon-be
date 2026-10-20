# frozen_string_literal: true

# Bulk voice calls. A `robocall_voices` row is one named call type ("Visa
# approved", "Flight") that points at a RoboCall voice id. An admin starts a
# `bulk_call_batches` row for the candidates at one workflow stage; each
# candidate in it is a `bulk_call_batch_items` row, which is what lets the next
# batch skip anyone already called and shows each candidate's result.
class CreateBulkCallTables < ActiveRecord::Migration[8.1]
  ITEM_STATUSES = "status IN ('queued', 'placed', 'skipped', 'failed')"
  ITEM_BATCH_INDEX = 'index_bulk_call_items_on_batch_and_candidate'

  def change
    create_robocall_voices
    create_bulk_call_batches
    create_bulk_call_batch_items
  end

  private

  def create_robocall_voices
    create_table :robocall_voices do |t|
      define_voice_columns(t)
      t.timestamps
    end
    add_index :robocall_voices, :public_id, unique: true
    add_index :robocall_voices, :voice_id, unique: true
    add_index :robocall_voices, 'lower(name_en)', unique: true, name: 'index_robocall_voices_on_lower_name_en'
  end

  def define_voice_columns(table)
    table.string :public_id, null: false
    table.string :name_en, null: false
    table.string :name_ur
    table.string :voice_id, null: false
    table.boolean :active, null: false, default: true
    table.references :created_by, foreign_key: { to_table: :users }
    table.references :updated_by, foreign_key: { to_table: :users }
  end

  def create_bulk_call_batches
    create_table :bulk_call_batches do |t|
      define_batch_columns(t)
      t.timestamps
    end
    add_index :bulk_call_batches, :public_id, unique: true
    add_index :bulk_call_batches, :created_at
    add_check_constraint :bulk_call_batches, 'requested_limit > 0 AND selected_count > 0',
                         name: 'bulk_call_batches_counts_positive'
  end

  # The voice id and name are snapshots, so a later edit of the voice does not rewrite history.
  def define_batch_columns(table)
    table.string :public_id, null: false
    table.references :created_by, null: false, foreign_key: { to_table: :users }
    table.references :robocall_voice, null: false, foreign_key: true
    table.string :provider_voice_id, null: false
    table.string :voice_name, null: false
    table.string :workflow_stage_code, null: false
    table.jsonb :filters, null: false, default: {}
    table.integer :requested_limit, null: false
    table.integer :selected_count, null: false
  end

  def create_bulk_call_batch_items
    create_table :bulk_call_batch_items do |t|
      define_item_columns(t)
      t.timestamps
    end
    add_index :bulk_call_batch_items, %i[bulk_call_batch_id candidate_id], unique: true, name: ITEM_BATCH_INDEX
    add_index :bulk_call_batch_items, %i[candidate_assignment_id status],
              name: 'index_bulk_call_items_on_assignment_and_status'
    add_check_constraint :bulk_call_batch_items, ITEM_STATUSES, name: 'bulk_call_batch_items_status'
  end

  def define_item_columns(table)
    table.references :bulk_call_batch, null: false, foreign_key: true
    table.references :candidate, null: false, foreign_key: true
    table.references :candidate_assignment, null: false, foreign_key: true
    table.references :candidate_ai_call, foreign_key: true
    table.string :status, null: false, default: 'queued'
    table.string :skip_reason
  end
end

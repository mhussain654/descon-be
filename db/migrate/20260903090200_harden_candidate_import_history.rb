# frozen_string_literal: true

class HardenCandidateImportHistory < ActiveRecord::Migration[8.1]
  def up
    change_table :candidate_import_batches, bulk: true do |table|
      table.change_null :preflight_payload, true
      table.datetime :enqueued_at
    end
    add_index :candidate_import_batches, %i[actor_id created_at]
  end

  def down
    remove_index :candidate_import_batches, %i[actor_id created_at]
    change_table :candidate_import_batches, bulk: true do |table|
      table.remove :enqueued_at
      table.change_null :preflight_payload, false
    end
  end
end

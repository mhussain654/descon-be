# frozen_string_literal: true

class HardenCandidateImportHistory < ActiveRecord::Migration[8.1]
  def change
    change_column_null :candidate_import_batches, :preflight_payload, true
    add_column :candidate_import_batches, :enqueued_at, :datetime
    add_index :candidate_import_batches, %i[actor_id created_at]
  end
end

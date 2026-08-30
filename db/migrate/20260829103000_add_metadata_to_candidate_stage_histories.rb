# frozen_string_literal: true

class AddMetadataToCandidateStageHistories < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = 'index_stage_histories_on_assignment_and_destination_stage'

  def up
    add_column :candidate_stage_histories, :metadata, :jsonb, default: {}, null: false

    add_index :candidate_stage_histories,
              %i[candidate_assignment_id to_workflow_stage_id],
              unique: true,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    remove_index :candidate_stage_histories, name: INDEX_NAME
    remove_column :candidate_stage_histories, :metadata
  end
end

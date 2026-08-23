# frozen_string_literal: true

class CreateCandidateHistoriesAndDocuments < ActiveRecord::Migration[8.1]
  def change
    create_candidate_stage_histories
    create_candidate_documents
  end

  private

  def create_candidate_stage_histories
    create_table :candidate_stage_histories do |t|
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :from_workflow_stage, foreign_key: { to_table: :workflow_stages }
      t.references :to_workflow_stage, null: false, foreign_key: { to_table: :workflow_stages }
      t.references :actor, foreign_key: { to_table: :users }
      t.datetime :occurred_at, null: false
      t.string :reason_code
      t.text :note

      t.timestamps
    end

    add_index :candidate_stage_histories,
              %i[candidate_assignment_id occurred_at],
              name: 'index_candidate_stage_histories_on_assignment_and_occurred_at'
    add_index :candidate_stage_histories,
              %i[from_workflow_stage_id occurred_at],
              name: 'index_candidate_stage_histories_on_from_stage_and_occurred_at'
    add_index :candidate_stage_histories,
              %i[to_workflow_stage_id occurred_at],
              name: 'index_candidate_stage_histories_on_to_stage_and_occurred_at'
  end

  def create_candidate_documents
    create_table :candidate_documents do |t|
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :document_type, null: false, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.references :verified_by, foreign_key: { to_table: :users }
      t.string :status_code, null: false
      t.string :original_filename
      t.string :content_type
      t.bigint :byte_size
      t.string :checksum_sha256
      t.string :document_number
      t.date :issued_on
      t.date :expires_on
      t.datetime :uploaded_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.datetime :verified_at
      t.text :rejection_reason

      t.timestamps
    end

    add_index :candidate_documents,
              %i[candidate_assignment_id document_type_id status_code],
              name: 'index_candidate_documents_on_assignment_type_status'
    add_index :candidate_documents, :checksum_sha256
  end
end

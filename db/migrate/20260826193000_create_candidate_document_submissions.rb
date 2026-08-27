# frozen_string_literal: true

class CreateCandidateDocumentSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_candidate_document_submissions_table
    add_candidate_document_submissions_indexes
    add_candidate_document_submissions_constraints
  end

  private

  def create_candidate_document_submissions_table
    create_table :candidate_document_submissions do |t|
      t.references :candidate_assignment, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :status_code, null: false
      t.string :request_id
      t.datetime :submitted_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamps
    end
  end

  def add_candidate_document_submissions_indexes
    add_index :candidate_document_submissions, :public_id, unique: true
    add_index :candidate_document_submissions,
              %i[candidate_assignment_id submitted_at],
              name: 'index_candidate_doc_submissions_on_assignment_and_submitted_at'
  end

  def add_candidate_document_submissions_constraints
    add_check_constraint :candidate_document_submissions,
                         "status_code IN ('submitted')",
                         name: 'candidate_document_submissions_status_code'
  end
end

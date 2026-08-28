# frozen_string_literal: true

class CreateCandidateDocumentSubmissionItems < ActiveRecord::Migration[8.1]
  def change
    create_candidate_document_submission_items_table
    add_candidate_document_submission_items_indexes
    add_candidate_document_submission_items_constraints
  end

  private

  def create_candidate_document_submission_items_table
    create_table :candidate_document_submission_items do |t|
      submission_reference(t)
      document_reference(t)
      t.string :requirement_code, null: false
      t.boolean :required, null: false, default: false
      t.timestamps
    end
  end

  def add_candidate_document_submission_items_indexes
    add_index :candidate_document_submission_items,
              %i[candidate_document_submission_id requirement_code],
              unique: true,
              name: 'index_candidate_doc_submission_items_on_submission_and_code'
  end

  def add_candidate_document_submission_items_constraints
    add_check_constraint :candidate_document_submission_items,
                         "requirement_code ~ '^[a-z0-9_]+$'",
                         name: 'candidate_document_submission_items_requirement_code_format'
  end

  def document_reference(table)
    table.references :candidate_document,
                     null: false,
                     foreign_key: true,
                     index: { unique: true, name: 'index_candidate_doc_submission_items_on_document_id' }
  end

  def submission_reference(table)
    table.references :candidate_document_submission,
                     null: false,
                     foreign_key: true,
                     index: { name: 'index_candidate_doc_submission_items_on_submission_id' }
  end
end

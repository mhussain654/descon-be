# frozen_string_literal: true

class EnableCandidateDocumentUploads < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_candidate_document_columns
    backfill_public_ids!
    enforce_public_id!
    add_candidate_document_indexes
  end

  def down
    remove_index :candidate_documents, name: 'index_candidate_documents_on_current_requirement'
    remove_index :candidate_documents, :public_id

    change_table :candidate_documents, bulk: true do |table|
      table.remove :superseded_at
      table.remove :public_id
    end
  end

  private

  def add_candidate_document_columns
    change_table :candidate_documents, bulk: true do |table|
      table.string :public_id
      table.datetime :superseded_at
    end
  end

  def enforce_public_id!
    change_column_null :candidate_documents, :public_id, false
  end

  def add_candidate_document_indexes
    add_index :candidate_documents, :public_id, unique: true, algorithm: :concurrently
    add_index :candidate_documents,
              %i[candidate_assignment_id document_type_id],
              unique: true,
              where: 'superseded_at IS NULL',
              name: 'index_candidate_documents_on_current_requirement',
              algorithm: :concurrently
  end

  def backfill_public_ids!
    say_with_time 'Backfilling candidate document public IDs' do
      candidate_document_class.reset_column_information
      candidate_document_class.find_each do |document|
        document.public_id = SecureRandom.uuid
        document.save!(validate: false)
      end
    end
  end

  def candidate_document_class
    Class.new(ActiveRecord::Base) do
      self.table_name = 'candidate_documents'
    end
  end
end

# frozen_string_literal: true

class EnableCandidateDocumentUploads < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :candidate_documents, :public_id, :string
    add_column :candidate_documents, :superseded_at, :datetime

    backfill_public_ids!

    change_column_null :candidate_documents, :public_id, false
    add_index :candidate_documents, :public_id, unique: true, algorithm: :concurrently
    add_index :candidate_documents,
              %i[candidate_assignment_id document_type_id],
              unique: true,
              where: 'superseded_at IS NULL',
              name: 'index_candidate_documents_on_current_requirement',
              algorithm: :concurrently
  end

  def down
    remove_index :candidate_documents, name: 'index_candidate_documents_on_current_requirement'
    remove_index :candidate_documents, :public_id
    remove_column :candidate_documents, :superseded_at
    remove_column :candidate_documents, :public_id
  end

  private

  def backfill_public_ids!
    say_with_time 'Backfilling candidate document public IDs' do
      candidate_document_class.reset_column_information
      candidate_document_class.find_each do |document|
        document.update_columns(public_id: SecureRandom.uuid)
      end
    end
  end

  def candidate_document_class
    Class.new(ActiveRecord::Base) do
      self.table_name = 'candidate_documents'
    end
  end
end

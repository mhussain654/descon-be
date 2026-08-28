# frozen_string_literal: true

class AddPccConstraintsAndIndexesToCandidateDocuments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :candidate_documents,
              %i[document_type_id superseded_at expires_on],
              where: 'issued_on IS NOT NULL',
              name: 'index_candidate_documents_on_type_state_expiry',
              algorithm: :concurrently
  end

  def down
    remove_index :candidate_documents, name: 'index_candidate_documents_on_type_state_expiry'
  end
end

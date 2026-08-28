# frozen_string_literal: true

class AddPccConstraintsAndIndexesToCandidateDocuments < ActiveRecord::Migration[8.1]
  EXPIRY_CONSISTENCY_CONSTRAINT = <<~SQL.squish.freeze
    ((issued_on IS NULL AND expires_on IS NULL) OR expires_on = ((issued_on + INTERVAL '6 months')::date))
  SQL

  disable_ddl_transaction!

  def up
    add_check_constraint :candidate_documents,
                         EXPIRY_CONSISTENCY_CONSTRAINT,
                         name: 'candidate_documents_pcc_expiry_consistency'

    add_index :candidate_documents,
              %i[document_type_id superseded_at expires_on],
              where: 'issued_on IS NOT NULL',
              name: 'index_candidate_documents_on_type_state_expiry',
              algorithm: :concurrently
  end

  def down
    remove_index :candidate_documents, name: 'index_candidate_documents_on_type_state_expiry'
    remove_check_constraint :candidate_documents, name: 'candidate_documents_pcc_expiry_consistency'
  end
end

# frozen_string_literal: true

class RemoveCandidateDocumentPccExpiryConsistencyConstraint < ActiveRecord::Migration[8.1]
  def up
    return unless check_constraint_exists?(:candidate_documents, name: 'candidate_documents_pcc_expiry_consistency')

    remove_check_constraint :candidate_documents, name: 'candidate_documents_pcc_expiry_consistency'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'candidate_documents_pcc_expiry_consistency should not be restored'
  end
end

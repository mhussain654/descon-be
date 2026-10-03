# frozen_string_literal: true

# Each file of a multi-file document is previewed individually (by candidate
# and staff), so it needs its own non-guessable identifier.
class AddPublicIdToCandidateDocumentFiles < ActiveRecord::Migration[8.1]
  def up
    add_column :candidate_document_files, :public_id, :string
    execute 'UPDATE candidate_document_files SET public_id = gen_random_uuid()::text'
    change_column_null :candidate_document_files, :public_id, false
    add_index :candidate_document_files, :public_id, unique: true
  end

  def down
    remove_column :candidate_document_files, :public_id
  end
end

# frozen_string_literal: true

# A CandidateDocument stays the one logical document a candidate submits for
# a requirement (one review status, one version history); its actual files
# -- e.g. passport page 1 + page 2, CNIC front + back, or several
# certificates -- move to candidate_document_files, each with its own
# attachment and file metadata.
#
# Existing single-file documents are carried over as one file each: the file
# row copies the document's metadata and the existing ActiveStorage
# attachment is re-pointed at it (no blob is copied or re-uploaded).
class CreateCandidateDocumentFiles < ActiveRecord::Migration[8.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def up
    create_table :candidate_document_files do |t|
      t.references :candidate_document, null: false, foreign_key: true
      t.string :side_code
      t.integer :position, null: false
      t.string :original_filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :checksum_sha256, null: false
      t.timestamps
    end
    add_index :candidate_document_files, %i[candidate_document_id position], unique: true
    add_index :candidate_document_files, :checksum_sha256
    add_check_constraint :candidate_document_files, 'position > 0', name: 'candidate_document_files_position_positive'
    add_check_constraint :candidate_document_files, 'byte_size > 0', name: 'candidate_document_files_byte_size_positive'
    add_check_constraint :candidate_document_files, "side_code IS NULL OR side_code ~ '^[a-z0-9_]+$'",
                         name: 'candidate_document_files_side_code_format'

    move_existing_files
    change_table :candidate_documents, bulk: true do |t|
      t.remove_index :checksum_sha256
      t.remove :original_filename, :content_type, :byte_size, :checksum_sha256
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # rubocop:disable Metrics/MethodLength
  def move_existing_files
    execute <<~SQL.squish
      INSERT INTO candidate_document_files
        (candidate_document_id, side_code, position, original_filename, content_type, byte_size, checksum_sha256,
         created_at, updated_at)
      SELECT id, NULL, 1, original_filename, content_type, byte_size, COALESCE(checksum_sha256, ''),
             uploaded_at, updated_at
      FROM candidate_documents
    SQL
    execute <<~SQL.squish
      UPDATE active_storage_attachments attachments
      SET record_type = 'CandidateDocumentFile', record_id = files.id
      FROM candidate_document_files files
      WHERE attachments.record_type = 'CandidateDocument' AND attachments.name = 'file'
        AND attachments.record_id = files.candidate_document_id
    SQL
  end
  # rubocop:enable Metrics/MethodLength
end

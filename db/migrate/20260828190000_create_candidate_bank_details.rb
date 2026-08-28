# frozen_string_literal: true

class CreateCandidateBankDetails < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_bank_details do |t|
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.string :status_code, null: false, default: 'submitted'
      t.text :account_title, null: false
      t.text :account_number, null: false
      t.string :bank_name, null: false
      t.string :proof_filename, null: false
      t.string :proof_content_type, null: false
      t.bigint :proof_byte_size, null: false
      t.string :proof_checksum_sha256
      t.datetime :submitted_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.datetime :reviewed_at
      t.datetime :superseded_at

      t.timestamps
    end

    add_index :candidate_bank_details, :public_id, unique: true
    add_index :candidate_bank_details,
              :candidate_assignment_id,
              unique: true,
              where: 'superseded_at IS NULL',
              name: 'index_candidate_bank_details_on_current_assignment'
    add_index :candidate_bank_details,
              %i[candidate_assignment_id status_code],
              name: 'index_candidate_bank_details_on_assignment_status'

    add_check_constraint :candidate_bank_details,
                         "status_code = 'submitted'",
                         name: 'candidate_bank_details_status_code'
    add_check_constraint :candidate_bank_details,
                         'proof_byte_size > 0',
                         name: 'candidate_bank_details_proof_byte_size_positive'
  end
end

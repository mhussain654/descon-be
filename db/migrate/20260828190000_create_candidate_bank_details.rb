# frozen_string_literal: true

class CreateCandidateBankDetails < ActiveRecord::Migration[8.1]
  def change
    create_candidate_bank_details_table
    add_candidate_bank_detail_indexes
    add_candidate_bank_detail_constraints
  end

  private

  def create_candidate_bank_details_table
    create_table :candidate_bank_details do |t|
      add_candidate_references(t)
      add_bank_attributes(t)
      add_proof_attributes(t)
      add_lifecycle_attributes(t)
      t.timestamps
    end
  end

  def add_candidate_references(table)
    table.references :candidate_assignment, null: false, foreign_key: true
    table.references :reviewed_by, foreign_key: { to_table: :users }
  end

  def add_bank_attributes(table)
    table.string :public_id, null: false
    table.string :status_code, null: false, default: 'submitted'
    table.text :account_title, null: false
    table.text :account_number, null: false
    table.string :bank_name, null: false
  end

  def add_proof_attributes(table)
    table.string :proof_filename, null: false
    table.string :proof_content_type, null: false
    table.bigint :proof_byte_size, null: false
    table.string :proof_checksum_sha256
  end

  def add_lifecycle_attributes(table)
    table.datetime :submitted_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    table.datetime :reviewed_at
    table.datetime :superseded_at
  end

  def add_candidate_bank_detail_indexes
    add_index :candidate_bank_details, :public_id, unique: true
    add_index :candidate_bank_details,
              :candidate_assignment_id,
              unique: true,
              where: 'superseded_at IS NULL',
              name: 'index_candidate_bank_details_on_current_assignment'
    add_index :candidate_bank_details,
              %i[candidate_assignment_id status_code],
              name: 'index_candidate_bank_details_on_assignment_status'
  end

  def add_candidate_bank_detail_constraints
    add_check_constraint :candidate_bank_details,
                         "status_code = 'submitted'",
                         name: 'candidate_bank_details_status_code'
    add_check_constraint :candidate_bank_details,
                         'proof_byte_size > 0',
                         name: 'candidate_bank_details_proof_byte_size_positive'
  end
end

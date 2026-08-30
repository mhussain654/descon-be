# frozen_string_literal: true

class CreateCandidateQvcAttemptsAndProtectionRecords < ActiveRecord::Migration[8.1]
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :candidate_qvc_attempts do |t|
      t.references :candidate_assignment, null: false, foreign_key: true, index: false
      t.references :scheduled_by, null: false, foreign_key: { to_table: :users }
      t.references :outcome_recorded_by, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.integer :attempt_number, null: false
      t.date :appointment_date, null: false
      t.string :outcome_code
      t.boolean :no_show, null: false, default: false
      t.datetime :outcome_recorded_at
      t.text :internal_note

      t.timestamps
    end

    add_index :candidate_qvc_attempts, :public_id, unique: true
    add_index :candidate_qvc_attempts, %i[candidate_assignment_id attempt_number], unique: true,
              name: 'index_qvc_attempts_on_assignment_and_attempt_number'
    add_index :candidate_qvc_attempts, %i[candidate_assignment_id appointment_date],
              name: 'index_qvc_attempts_on_assignment_and_appointment_date'
    add_index :candidate_qvc_attempts, :no_show
    add_index :candidate_qvc_attempts, :outcome_code
    add_index :candidate_qvc_attempts, :outcome_recorded_at
    add_index :candidate_qvc_attempts, :candidate_assignment_id,
              unique: true,
              where: 'outcome_recorded_at IS NULL',
              name: 'index_qvc_attempts_on_assignment_when_open'
    add_check_constraint :candidate_qvc_attempts,
                         "public_id::text ~ '^[0-9a-f-]{36}$'::text",
                         name: 'candidate_qvc_attempts_public_id_format'
    add_check_constraint :candidate_qvc_attempts,
                         'attempt_number > 0',
                         name: 'candidate_qvc_attempts_attempt_number_positive'
    add_check_constraint :candidate_qvc_attempts,
                         "outcome_code IS NULL OR outcome_code::text IN ('approved', 're_medical', 'rejected')",
                         name: 'candidate_qvc_attempts_outcome_code_values'
    add_check_constraint :candidate_qvc_attempts,
                         'NOT (no_show = TRUE AND outcome_code IS NOT NULL)',
                         name: 'candidate_qvc_attempts_no_show_outcome_exclusive'
    add_check_constraint :candidate_qvc_attempts,
                         '((outcome_code IS NULL AND no_show = FALSE AND outcome_recorded_at IS NULL AND outcome_recorded_by_id IS NULL) OR ((outcome_code IS NOT NULL OR no_show = TRUE) AND outcome_recorded_at IS NOT NULL AND outcome_recorded_by_id IS NOT NULL))',
                         name: 'candidate_qvc_attempts_outcome_fields_consistent'

    create_table :candidate_protection_records do |t|
      t.references :candidate_assignment, null: false, foreign_key: true, index: false
      t.references :appeared_recorded_by, foreign_key: { to_table: :users }
      t.references :ready_recorded_by, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.date :appeared_on
      t.datetime :appeared_recorded_at
      t.date :protected_on
      t.datetime :ready_to_fly_at

      t.timestamps
    end

    add_index :candidate_protection_records, :public_id, unique: true
    add_index :candidate_protection_records, :candidate_assignment_id, unique: true
    add_index :candidate_protection_records, :appeared_on
    add_index :candidate_protection_records, :ready_to_fly_at
    add_check_constraint :candidate_protection_records,
                         "public_id::text ~ '^[0-9a-f-]{36}$'::text",
                         name: 'candidate_protection_records_public_id_format'
    add_check_constraint :candidate_protection_records,
                         '((appeared_on IS NULL AND appeared_recorded_at IS NULL AND appeared_recorded_by_id IS NULL) OR (appeared_on IS NOT NULL AND appeared_recorded_at IS NOT NULL AND appeared_recorded_by_id IS NOT NULL))',
                         name: 'candidate_protection_records_appearance_fields_consistent'
    add_check_constraint :candidate_protection_records,
                         '((protected_on IS NULL AND ready_to_fly_at IS NULL AND ready_recorded_by_id IS NULL) OR (protected_on IS NOT NULL AND ready_to_fly_at IS NOT NULL AND ready_recorded_by_id IS NOT NULL))',
                         name: 'candidate_protection_records_ready_fields_consistent'
    add_check_constraint :candidate_protection_records,
                         '(protected_on IS NULL OR appeared_on IS NOT NULL)',
                         name: 'candidate_protection_records_ready_requires_appearance'
  end
  # rubocop:enable Metrics/MethodLength
end

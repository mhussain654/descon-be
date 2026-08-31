# frozen_string_literal: true

class CreateCandidateVisaDecisions < ActiveRecord::Migration[8.1]
  OUTCOME_FIELDS_CONSTRAINT = <<~SQL.squish.freeze
    (
      (outcome_code = 'issued' AND rejection_reason_code IS NULL) OR
      (outcome_code = 'rejected' AND rejection_reason_code IS NOT NULL)
    )
  SQL

  def change
    create_table :candidate_visa_decisions do |t|
      t.references :candidate_assignment, null: false, foreign_key: true, index: false
      t.references :candidate_stage_history, null: false, foreign_key: true, index: { unique: true }
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.string :outcome_code, null: false
      t.date :decision_date, null: false
      t.string :rejection_reason_code
      t.timestamps
    end

    add_index :candidate_visa_decisions, :public_id, unique: true
    add_index :candidate_visa_decisions, %i[candidate_assignment_id created_at],
              name: 'index_visa_decisions_on_assignment_and_created_at'
    add_index :candidate_visa_decisions, :outcome_code

    add_check_constraint :candidate_visa_decisions,
                         "public_id::text ~ '^[0-9a-f-]{36}$'::text",
                         name: 'candidate_visa_decisions_public_id_format'
    add_check_constraint :candidate_visa_decisions,
                         "outcome_code::text IN ('issued', 'rejected')",
                         name: 'candidate_visa_decisions_outcome_code_values'
    add_check_constraint :candidate_visa_decisions,
                         OUTCOME_FIELDS_CONSTRAINT,
                         name: 'candidate_visa_decisions_rejection_reason_consistent'
  end
end

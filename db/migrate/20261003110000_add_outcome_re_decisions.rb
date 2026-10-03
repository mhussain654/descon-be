# frozen_string_literal: true

# Negative outcomes hold a candidate at their outcome stage and can be
# re-decided there (BE PR 3):
#
# * A visa decision is recorded either by the transition into the visa stage
#   (linked to that stage-history entry) or, while the candidate is held at
#   that stage, as a later re-decision with no transition -- so the history
#   link becomes optional.
# * Medical results (fit/unfit) get their own record on the same pattern.
#
# The latest decision of each kind decides whether the candidate may leave
# the stage; every decision is kept.
class AddOutcomeReDecisions < ActiveRecord::Migration[8.1]
  # rubocop:disable Metrics/MethodLength
  def change
    change_column_null :candidate_visa_decisions, :candidate_stage_history_id, true

    create_table :candidate_medical_results do |t|
      t.string :public_id, null: false
      t.references :candidate_assignment, null: false, foreign_key: true
      t.references :candidate_stage_history, foreign_key: true, index: { unique: true }
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }
      t.string :outcome_code, null: false
      t.date :result_date, null: false
      t.text :note
      t.timestamps
    end
    add_index :candidate_medical_results, :public_id, unique: true
    add_index :candidate_medical_results, %i[candidate_assignment_id created_at],
              name: 'index_medical_results_on_assignment_and_created_at'
    add_check_constraint :candidate_medical_results, "outcome_code IN ('fit', 'unfit')",
                         name: 'candidate_medical_results_outcome_code_values'
  end
  # rubocop:enable Metrics/MethodLength
end

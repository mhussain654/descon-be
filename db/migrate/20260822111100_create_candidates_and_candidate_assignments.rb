# frozen_string_literal: true

class CreateCandidatesAndCandidateAssignments < ActiveRecord::Migration[8.1]
  def change
    create_candidates
    create_candidate_assignments
  end

  private

  def create_candidates
    create_table :candidates do |t|
      t.string :public_id, null: false
      t.string :full_name, null: false
      t.string :cnic, null: false
      t.string :mobile_number, null: false
      t.string :passport_number
      t.string :preferred_locale, null: false, default: 'en'
      t.string :source_code, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :candidates, :public_id, unique: true
    add_index :candidates, :cnic, unique: true
    add_index :candidates, :passport_number, unique: true, where: 'passport_number IS NOT NULL'
    add_index :candidates, :mobile_number
    add_index :candidates, %i[created_by_id created_at]
  end

  def create_candidate_assignments
    create_table :candidate_assignments do |t|
      t.string :public_id, null: false
      t.references :candidate, null: false, foreign_key: true
      t.references :country, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :craft, null: false, foreign_key: true
      t.string :reference_number, null: false
      t.references :current_workflow_stage, null: false, foreign_key: { to_table: :workflow_stages }
      t.string :qvc_outcome_code
      t.date :qvc_outcome_date
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :candidate_assignments, :public_id, unique: true
    add_index :candidate_assignments, :reference_number, unique: true
    add_index :candidate_assignments, %i[candidate_id created_at]
    add_index :candidate_assignments,
              %i[current_workflow_stage_id created_at],
              name: 'index_candidate_assignments_on_stage_and_created_at'
    add_index :candidate_assignments,
              %i[project_id craft_id country_id],
              name: 'index_candidate_assignments_on_project_craft_country'
  end
end

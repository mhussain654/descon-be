# frozen_string_literal: true

class CreateCandidateFlightDetails < ActiveRecord::Migration[8.1]
  MOBILIZATION_FIELDS_CONSTRAINT = <<~SQL.squish.freeze
    (
      (mobilized_on IS NULL AND mobilized_stage_history_id IS NULL AND mobilized_recorded_by_id IS NULL) OR
      (mobilized_on IS NOT NULL AND mobilized_stage_history_id IS NOT NULL AND mobilized_recorded_by_id IS NOT NULL)
    )
  SQL
  DATE_SEQUENCE_CONSTRAINT = <<~SQL.squish.freeze
    (mobilized_on IS NULL OR mobilized_on >= flight_departure_at::date)
  SQL

  def change
    create_table :candidate_flight_details do |t|
      t.references :candidate_assignment, null: false, foreign_key: true, index: { unique: true }
      t.references :candidate_stage_history, null: false, foreign_key: true, index: { unique: true }
      t.references :mobilized_stage_history, foreign_key: { to_table: :candidate_stage_histories },
                                             index: { unique: true }
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }
      t.references :mobilized_recorded_by, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.string :airline, null: false
      t.string :flight_number, null: false
      t.string :sector, null: false
      t.datetime :flight_departure_at, null: false
      t.date :mobilized_on
      t.timestamps
    end

    add_index :candidate_flight_details, :public_id, unique: true
    add_index :candidate_flight_details, :flight_departure_at
    add_index :candidate_flight_details, :mobilized_on

    add_check_constraint :candidate_flight_details,
                         "public_id::text ~ '^[0-9a-f-]{36}$'::text",
                         name: 'candidate_flight_details_public_id_format'
    add_check_constraint :candidate_flight_details,
                         MOBILIZATION_FIELDS_CONSTRAINT,
                         name: 'candidate_flight_details_mobilization_fields_consistent'
    add_check_constraint :candidate_flight_details,
                         DATE_SEQUENCE_CONSTRAINT,
                         name: 'candidate_flight_details_mobilized_on_sequence'
  end
end

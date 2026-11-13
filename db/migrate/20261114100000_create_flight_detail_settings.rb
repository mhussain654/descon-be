# frozen_string_literal: true

# The single admin-editable row holding the default flight details: airline,
# flight number, sector and departure date and time, filled in when staff add a
# candidate's flight details. Each candidate's own copy is saved with their flight
# details, so changing these defaults later only affects candidates added
# afterwards. Same singleton shape as CreateMedicalAppointmentSettings.
class CreateFlightDetailSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :flight_detail_settings do |t|
      t.boolean :singleton_guard, null: false, default: true
      t.string :airline, :flight_number, :sector
      t.date :departure_on
      t.string :departure_time
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_singleton_and_time_constraints
  end

  private

  def add_singleton_and_time_constraints
    add_index :flight_detail_settings, :singleton_guard, unique: true
    add_check_constraint :flight_detail_settings,
                         "departure_time IS NULL OR departure_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'",
                         name: 'flight_detail_settings_time_format'
  end
end

# frozen_string_literal: true

# The single admin-editable row holding the default medical appointment: the
# centre, its address, and the date and time staff fill in for candidates moved
# into a medical appointment stage. Each move saves its own copy on the
# candidate's stage history, so changing these defaults later only affects
# candidates moved afterwards. Same singleton shape as CreateSupportSettings.
class CreateMedicalAppointmentSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :medical_appointment_settings do |t|
      t.boolean :singleton_guard, null: false, default: true
      t.string :center_name
      t.text :center_address
      t.date :appointment_on
      t.string :appointment_time
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_singleton_and_time_constraints
  end

  private

  def add_singleton_and_time_constraints
    add_index :medical_appointment_settings, :singleton_guard, unique: true
    add_check_constraint :medical_appointment_settings,
                         "appointment_time IS NULL OR appointment_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'",
                         name: 'medical_appointment_settings_time_format'
  end
end

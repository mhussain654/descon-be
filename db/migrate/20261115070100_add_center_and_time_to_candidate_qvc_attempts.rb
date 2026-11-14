# frozen_string_literal: true

# A QVC booking used to hold only the date. It now also keeps the centre, its
# address and the time (all optional), so the candidate app can show where and
# when to go, the same as for the medical appointment.
class AddCenterAndTimeToCandidateQvcAttempts < ActiveRecord::Migration[8.1]
  def change
    change_table :candidate_qvc_attempts, bulk: true do |t|
      t.string :center_name
      t.text :center_address
      t.string :appointment_time
    end

    add_check_constraint :candidate_qvc_attempts,
                         "appointment_time IS NULL OR appointment_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'",
                         name: 'candidate_qvc_attempts_time_format'
  end
end

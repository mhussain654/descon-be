# frozen_string_literal: true

# The automatic check of an uploaded boarding pass (OCR compares it with the
# booked flight) and a staff member's rejection of one that isn't valid.
class AddBoardingPassCheckAndRejectionToCandidateFlightDetails < ActiveRecord::Migration[8.1]
  CHECK_VALUES = "'pending', 'matched', 'needs_review', 'not_boarding_pass', 'unavailable'"
  REJECTION_FIELDS = %w[boarding_pass_rejected_at boarding_pass_rejected_by_id boarding_pass_rejection_reason].freeze

  def change
    add_columns
    add_check_constraint :candidate_flight_details,
                         "boarding_pass_check IS NULL OR boarding_pass_check IN (#{CHECK_VALUES})",
                         name: 'candidate_flight_details_boarding_pass_check_values'
    add_check_constraint :candidate_flight_details, rejection_fields_together,
                         name: 'candidate_flight_details_boarding_pass_rejection_consistent'
  end

  private

  def add_columns
    change_table :candidate_flight_details, bulk: true do |t|
      t.string :boarding_pass_check
      t.jsonb :boarding_pass_check_signals, null: false, default: {}
      t.string :boarding_pass_seat, limit: 8
      t.datetime :boarding_pass_checked_at
      t.datetime :boarding_pass_rejected_at
      t.references :boarding_pass_rejected_by, foreign_key: { to_table: :users }
      t.string :boarding_pass_rejection_reason, limit: 500
    end
  end

  # A rejection records when, by whom and why, all together or not at all.
  def rejection_fields_together
    "(#{REJECTION_FIELDS.map { |field| "#{field} IS NULL" }.join(' AND ')}) OR " \
      "(#{REJECTION_FIELDS.map { |field| "#{field} IS NOT NULL" }.join(' AND ')})"
  end
end

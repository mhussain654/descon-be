# frozen_string_literal: true

# The route ("sector", e.g. Lahore to Doha) is optional when staff add a candidate's
# flight details (client decision, Nov 2026): many staff and candidates do not use
# the word, and the airline, flight number and departure already identify the flight.
class AllowBlankSectorOnCandidateFlightDetails < ActiveRecord::Migration[8.1]
  def change
    change_column_null :candidate_flight_details, :sector, true
  end
end

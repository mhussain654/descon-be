# frozen_string_literal: true

# The candidate's own photo of their boarding pass (client request, Nov 2026),
# attached to their flight record. The timestamp lets MPS staff filter who has
# uploaded one and who has not; the index serves that filter.
class AddBoardingPassToCandidateFlightDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :candidate_flight_details, :boarding_pass_uploaded_at, :datetime
    add_index :candidate_flight_details, :boarding_pass_uploaded_at
  end
end

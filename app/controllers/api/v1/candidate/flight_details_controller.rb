# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate view their booked flight details for their current deployment assignment.
      class FlightDetailsController < ProtectedController
        # Returns the current candidate's flight details (if any have been recorded yet),
        # with cache/ETag headers reflecting the assignment's last update time.
        def show
          authorize current_candidate, policy_class: ::Candidates::WorkflowPolicy

          set_private_state_headers(
            updated_at: current_candidate.current_assignment&.updated_at,
            etag_key: "#{current_candidate.public_id}:flight_detail"
          )
          render_success(data: serialized_flight_detail)
        end

        private

        # Serializes the current assignment's flight detail record, or a blank representation if none exists yet.
        def serialized_flight_detail
          detail = current_candidate.current_assignment&.candidate_flight_detail
          ::CandidateWorkflows::FlightDetailSerializer.new(detail).as_json
        end
      end
    end
  end
end

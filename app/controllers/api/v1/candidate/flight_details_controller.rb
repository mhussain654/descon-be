# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class FlightDetailsController < ProtectedController
        def show
          authorize current_candidate, policy_class: ::Candidates::WorkflowPolicy

          set_private_state_headers(
            updated_at: current_candidate.current_assignment&.updated_at,
            etag_key: "#{current_candidate.public_id}:flight_detail"
          )
          render_success(data: serialized_flight_detail)
        end

        private

        def serialized_flight_detail
          detail = current_candidate.current_assignment&.candidate_flight_detail
          ::CandidateWorkflows::FlightDetailSerializer.new(detail).as_json
        end
      end
    end
  end
end

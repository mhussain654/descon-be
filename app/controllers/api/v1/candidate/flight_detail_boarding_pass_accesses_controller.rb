# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Gives the logged-in candidate a short-lived, audited link to view the
      # boarding pass photo they uploaded, so they can check it is the right one.
      class FlightDetailBoardingPassAccessesController < ProtectedController
        def create
          authorize current_candidate, :access?, policy_class: ::Candidates::WorkflowPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::CandidateWorkflows::FlightTicketAccessSerializer.new(access_result).as_json)
        end

        private

        def access_result
          ::CandidateWorkflows::FlightTicketAccessService.call(
            actor: nil, candidate: current_candidate, detail: flight_detail,
            request_id: request.request_id, attachment: :boarding_pass
          )
        end

        def flight_detail
          current_candidate.current_assignment&.candidate_flight_detail || raise(NotFoundError)
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets the logged-in candidate record and retrieve access to their own flight ticket details.
      class FlightDetailTicketAccessesController < ProtectedController
        # Records that the candidate accessed their flight ticket and returns the ticket access details.
        def create
          authorize current_candidate, :access?, policy_class: ::Candidates::WorkflowPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::CandidateWorkflows::FlightTicketAccessSerializer.new(access_result).as_json)
        end

        private

        # Logs the ticket access via the access service, memoized per request.
        def access_result
          @access_result ||= ::CandidateWorkflows::FlightTicketAccessService.call(
            actor: nil,
            candidate: current_candidate,
            detail: flight_detail,
            request_id: request.request_id
          )
        end

        # Finds the candidate's current flight detail, raising a 404 if none exists yet.
        def flight_detail
          @flight_detail ||= current_candidate.current_assignment&.candidate_flight_detail.tap do |detail|
            raise NotFoundError if detail.blank?
          end
        end
      end
    end
  end
end

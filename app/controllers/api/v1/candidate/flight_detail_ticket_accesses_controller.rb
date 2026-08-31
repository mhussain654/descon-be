# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class FlightDetailTicketAccessesController < ProtectedController
        def create
          authorize current_candidate, :access?, policy_class: ::Candidates::WorkflowPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::CandidateWorkflows::FlightTicketAccessSerializer.new(access_result).as_json)
        end

        private

        def access_result
          @access_result ||= ::CandidateWorkflows::FlightTicketAccessService.call(
            actor: nil,
            candidate: current_candidate,
            detail: flight_detail,
            request_id: request.request_id
          )
        end

        def flight_detail
          @flight_detail ||= current_candidate.current_assignment&.candidate_flight_detail.tap do |detail|
            raise NotFoundError if detail.blank?
          end
        end
      end
    end
  end
end

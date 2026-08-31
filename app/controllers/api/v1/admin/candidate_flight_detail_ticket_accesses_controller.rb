# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateFlightDetailTicketAccessesController < ProtectedStaffController
        def create
          authorize candidate, :access?, policy_class: ::Admin::CandidateWorkflowPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::CandidateWorkflows::FlightTicketAccessSerializer.new(access_result).as_json)
        end

        private

        def access_result
          @access_result ||= ::CandidateWorkflows::FlightTicketAccessService.call(
            actor: current_user,
            candidate: candidate,
            detail: flight_detail,
            request_id: request.request_id
          )
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def flight_detail
          @flight_detail ||= candidate.current_assignment&.candidate_flight_detail.tap do |detail|
            raise NotFoundError if detail.blank?
          end
        end
      end
    end
  end
end

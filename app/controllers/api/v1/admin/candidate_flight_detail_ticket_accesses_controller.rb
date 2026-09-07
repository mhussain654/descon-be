# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff record and retrieve access to a candidate's flight ticket details on their behalf.
      class CandidateFlightDetailTicketAccessesController < ProtectedStaffController
        # Records that this staff member accessed the candidate's flight ticket and returns the
        # ticket access details.
        def create
          authorize candidate, :access?, policy_class: ::Admin::CandidateWorkflowPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::CandidateWorkflows::FlightTicketAccessSerializer.new(access_result).as_json)
        end

        private

        # Logs the ticket access via the access service, memoized per request.
        def access_result
          @access_result ||= ::CandidateWorkflows::FlightTicketAccessService.call(
            actor: current_user,
            candidate: candidate,
            detail: flight_detail,
            request_id: request.request_id
          )
        end

        # Loads the candidate for this action within the staff member's authorized scope,
        # raising if not found.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        # Finds the candidate's current flight detail, raising a 404 if none exists yet.
        def flight_detail
          @flight_detail ||= candidate.current_assignment&.candidate_flight_detail.tap do |detail|
            raise NotFoundError if detail.blank?
          end
        end
      end
    end
  end
end

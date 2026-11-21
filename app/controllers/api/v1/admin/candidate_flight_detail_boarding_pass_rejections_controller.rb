# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets document reviewers and staff who manage the workflow reject a
      # candidate's boarding pass photo that isn't a valid boarding pass, with a reason.
      class CandidateFlightDetailBoardingPassRejectionsController < ProtectedStaffController
        def create
          authorize candidate, :reject_boarding_pass?, policy_class: ::Admin::CandidateWorkflowPolicy

          detail = ::CandidateWorkflows::FlightDetails::BoardingPassRejectionService.call(
            actor: current_user, candidate:, reason: params.expect(boarding_pass_rejection: [:reason])[:reason],
            request_id: request.request_id
          )
          render_success(data: ::CandidateWorkflows::AdminFlightDetailSerializer.new(detail).as_json, status: :created)
        end

        private

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end
      end
    end
  end
end

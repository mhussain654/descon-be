# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets the logged-in candidate record and retrieve access to their own visa copy.
      class VisaDecisionVisaCopyAccessesController < ProtectedController
        # Records that the candidate accessed their visa copy and returns the access details.
        def create
          authorize current_candidate, :access?, policy_class: ::Candidates::WorkflowPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::CandidateWorkflows::VisaCopyAccessSerializer.new(access_result).as_json)
        end

        private

        # Requests and memoizes the signed access result from the shared visa-copy access service.
        def access_result
          @access_result ||= ::CandidateWorkflows::VisaCopyAccessService.call(
            actor: nil,
            candidate: current_candidate,
            decision: visa_decision,
            request_id: request.request_id
          )
        end

        # Finds the candidate's own visa decision named in the route, raising a 404 if not found --
        # scoped to their current assignment, so a candidate can never reach another candidate's decision.
        def visa_decision
          @visa_decision ||= begin
            assignment = current_candidate.current_assignment
            decision = assignment&.candidate_visa_decisions&.find_by(public_id: params.expect(:visa_decision_id))
            raise NotFoundError if decision.blank?

            decision
          end
        end
      end
    end
  end
end

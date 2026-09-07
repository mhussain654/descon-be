# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Issues a short-lived signed URL so staff can view a candidate's
      # uploaded visa copy for a specific visa decision, and records the
      # access for audit purposes.
      class CandidateVisaDecisionVisaCopyAccessesController < ProtectedStaffController
        # Grants (and returns) time-limited access to the visa copy file
        # attached to the given visa decision; never cached by the browser.
        def create
          authorize candidate, :access?, policy_class: ::Admin::CandidateWorkflowPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::Admin::VisaDecisionAccessSerializer.new(access_result).as_json)
        end

        private

        # Requests and memoizes the signed access result from the visa-copy
        # access service, which also logs the access for audit purposes.
        def access_result
          @access_result ||= ::Admin::CandidateVisaDecisions::VisaCopyAccessService.call(
            actor: current_user,
            decision: visa_decision,
            request_id: request.request_id
          )
        end

        # Loads the candidate named in the route, scoped to what the current
        # staff member is authorized to view/manage.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        # Loads the candidate's visa decision named in the route, raising if
        # no matching decision exists on their current assignment.
        def visa_decision
          @visa_decision ||= begin
            assignment = candidate.current_assignment
            decision = assignment&.candidate_visa_decisions&.find_by(public_id: params.expect(:visa_decision_id))
            raise NotFoundError if decision.blank?

            decision
          end
        end
      end
    end
  end
end

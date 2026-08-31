# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateVisaDecisionVisaCopyAccessesController < ProtectedStaffController
        def create
          authorize candidate, :access?, policy_class: ::Admin::CandidateWorkflowPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(data: ::Admin::VisaDecisionAccessSerializer.new(access_result).as_json)
        end

        private

        def access_result
          @access_result ||= ::Admin::CandidateVisaDecisions::VisaCopyAccessService.call(
            actor: current_user,
            decision: visa_decision,
            request_id: request.request_id
          )
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

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

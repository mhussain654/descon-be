# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Returns the current workflow-stage snapshot for a single candidate.
      class CandidateWorkflowStatesController < ProtectedStaffController
        # Returns the candidate's current workflow stage and related state.
        def show
          authorize candidate, :show?, policy_class: ::Admin::CandidateWorkflowPolicy

          snapshot = ::CandidateWorkflows::StateSnapshotService.call(candidate:)
          set_private_state_headers(updated_at: candidate.current_assignment&.updated_at, etag_key: candidate.public_id)

          render_success(data: ::CandidateWorkflows::StateSerializer.new(snapshot).as_json)
        end

        private

        # Loads the candidate named in the route, scoped to what the current
        # staff member is authorized to view/manage.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end
      end
    end
  end
end

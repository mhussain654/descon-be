# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view a candidate's workflow history, including which staff member acted on
      # each transition.
      class CandidateWorkflowHistoriesController < ProtectedStaffController
        # Returns the candidate's stage-by-stage workflow history as a state snapshot, with actor
        # attribution on each history entry.
        def show
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy

          snapshot = ::CandidateWorkflows::StateSnapshotService.call(candidate:, include_history_actor: true)
          set_private_state_headers(
            updated_at: candidate.current_assignment&.updated_at,
            etag_key: "#{candidate.public_id}:history"
          )

          render_success(data: ::CandidateWorkflows::AdminHistorySerializer.new(snapshot).as_json)
        end

        private

        # Loads the candidate for this action within the staff member's authorized scope,
        # raising if not found.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Candidate
      # Lets a candidate view where they currently stand in the multi-stage recruitment/deployment workflow.
      class WorkflowStatesController < ProtectedController
        # Returns a snapshot of the current candidate's workflow state (current stage and related status),
        # with cache/ETag headers reflecting the assignment's last update time.
        def show
          authorize current_candidate, policy_class: ::Candidates::WorkflowPolicy

          snapshot = ::CandidateWorkflows::StateSnapshotService.call(candidate: current_candidate)
          set_private_state_headers(
            updated_at: current_candidate.current_assignment&.updated_at,
            etag_key: current_candidate.public_id
          )

          render_success(data: ::CandidateWorkflows::StateSerializer.new(snapshot).as_json)
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class WorkflowStatesController < ProtectedController
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

# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidateWorkflowStatesController < ProtectedStaffController
        def show
          authorize candidate, :show?, policy_class: ::Admin::CandidateWorkflowPolicy

          snapshot = ::CandidateWorkflows::StateSnapshotService.call(candidate:)
          set_private_state_headers(updated_at: candidate.current_assignment&.updated_at, etag_key: candidate.public_id)

          render_success(data: ::CandidateWorkflows::StateSerializer.new(snapshot).as_json)
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

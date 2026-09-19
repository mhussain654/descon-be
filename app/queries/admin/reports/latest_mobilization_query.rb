# frozen_string_literal: true

module Admin
  module Reports
    # The single most recently mobilized candidate (MPS-802 Operations
    # dashboard "Latest mobilization" card) -- the newest
    # CandidateStageHistory row whose destination is the terminal
    # 'mobilized' stage, enriched with the assignment's country/project/
    # craft for display. Returns nil when nothing has been mobilized yet in
    # scope, never a fabricated placeholder row.
    class LatestMobilizationQuery < ApplicationQuery
      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        history = latest_mobilization_history
        return nil unless history

        row_for(history)
      end

      private

      def row_for(history)
        candidate_attributes(history.candidate_assignment).merge(mobilized_at: history.occurred_at)
      end

      def candidate_attributes(assignment)
        {
          candidate_full_name: assignment.candidate.full_name,
          candidate_public_id: assignment.candidate.public_id,
          candidate_assignment_public_id: assignment.public_id,
          reference_number: assignment.reference_number,
          country_name: assignment.country.name_for,
          project_name: assignment.project.name_for,
          craft_name: assignment.craft.name_for
        }
      end

      def latest_mobilization_history
        CandidateStageHistory
          .where(to_workflow_stage_id: mobilized_stage_id, candidate_assignment_id: assignment_ids)
          .includes(candidate_assignment: %i[candidate country project craft])
          .order(occurred_at: :desc)
          .first
      end

      def assignment_ids
        @assignment_ids ||= CurrentAssignmentJoin.call(scope: @scope).select('current_assignments.id')
      end

      def mobilized_stage_id
        @mobilized_stage_id ||= WorkflowStage.find_by!(code: 'mobilized').id
      end
    end
  end
end

# frozen_string_literal: true

module Admin
  module Reports
    # Candidates whose current assignment has sat in its current (non-terminal)
    # stage longer than a threshold (MPS-802). The requirements doc does not
    # define "delayed"/"critical" thresholds -- 7 and 14 days are used as a
    # documented implementation-time default, not a confirmed stakeholder
    # value. `critical` candidates are also counted in `delayed` (a floor,
    # same "reached at least" convention as ConversionQuery), not a separate
    # band, since a dashboard chip for "at least this stale" is the more
    # common shape and avoids a double-counting question at the boundary.
    class DelayedCasesQuery < ApplicationQuery
      DELAYED_THRESHOLD = 7.days
      CRITICAL_THRESHOLD = 14.days
      TERMINAL_STAGE_CODE = 'mobilized'

      def initialize(scope: Candidate.all, reference_time: Time.current)
        super()
        @scope = scope
        @reference_time = reference_time
      end

      def call
        { delayed: count_stale_since(DELAYED_THRESHOLD), critical: count_stale_since(CRITICAL_THRESHOLD) }
      end

      private

      def count_stale_since(threshold)
        cutoff = @reference_time - threshold
        non_terminal_scope.where(
          'COALESCE(stage_entries.occurred_at, current_assignments.created_at) <= ?', cutoff
        ).count
      end

      def non_terminal_scope
        @non_terminal_scope ||= begin
          joined = CurrentAssignmentJoin.call(scope: @scope).joins(stage_entry_join_sql)
          joined.where.not(current_assignments: { current_workflow_stage_id: terminal_stage_id })
        end
      end

      def stage_entry_join_sql
        <<~SQL.squish
          LEFT JOIN candidate_stage_histories stage_entries
            ON stage_entries.candidate_assignment_id = current_assignments.id
            AND stage_entries.to_workflow_stage_id = current_assignments.current_workflow_stage_id
        SQL
      end

      def terminal_stage_id
        @terminal_stage_id ||= WorkflowStage.find_by!(code: TERMINAL_STAGE_CODE).id
      end
    end
  end
end

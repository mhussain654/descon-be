# frozen_string_literal: true

module Admin
  module Reports
    # Candidates whose current assignment has sat in its current (non-terminal)
    # stage longer than a threshold (MPS-802). The requirements doc does not
    # define "delayed"/"critical" thresholds -- 7 and 14 days are used as a
    # documented implementation-time default, not a confirmed stakeholder
    # value, and are read from ENV precisely so ops/product can correct them
    # without a code deploy once the client confirms real numbers (matching
    # this app's established "if approved" credential/threshold pattern --
    # see BACKUP_RETENTION_DAYS). `critical` candidates are also counted in
    # `delayed` (a floor, same "reached at least" convention as
    # ConversionQuery), not a separate band, since a dashboard chip for "at
    # least this stale" is the more common shape and avoids a
    # double-counting question at the boundary.
    class DelayedCasesQuery < ApplicationQuery
      DELAYED_THRESHOLD = ENV.fetch('DASHBOARD_DELAYED_THRESHOLD_DAYS', '7').to_i.days
      CRITICAL_THRESHOLD = ENV.fetch('DASHBOARD_CRITICAL_THRESHOLD_DAYS', '14').to_i.days
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
          'COALESCE(latest_stage_entry.occurred_at, current_assignments.created_at) <= ?', cutoff
        ).distinct.count('current_assignments.id')
      end

      # A candidate assignment can enter the same workflow stage more than
      # once (e.g. bounced back and re-advanced) -- candidate_stage_histories
      # then has multiple rows matching (candidate_assignment_id,
      # to_workflow_stage_id), and a plain LEFT JOIN on that pair fans out,
      # counting the same assignment once per matching history row. The
      # LATERAL subquery picks only the single *latest* entry into the
      # current stage per assignment, so the join (and the distinct count
      # above, as a second line of defense) can never multiply a candidate.
      def non_terminal_scope
        @non_terminal_scope ||= begin
          joined = CurrentAssignmentJoin.call(scope: @scope).joins(latest_stage_entry_join_sql)
          joined.where.not(current_assignments: { current_workflow_stage_id: terminal_stage_id })
        end
      end

      def latest_stage_entry_join_sql
        <<~SQL.squish
          LEFT JOIN LATERAL (
            SELECT csh.occurred_at
            FROM candidate_stage_histories csh
            WHERE csh.candidate_assignment_id = current_assignments.id
              AND csh.to_workflow_stage_id = current_assignments.current_workflow_stage_id
            ORDER BY csh.occurred_at DESC
            LIMIT 1
          ) latest_stage_entry ON true
        SQL
      end

      def terminal_stage_id
        @terminal_stage_id ||= WorkflowStage.find_by!(code: TERMINAL_STAGE_CODE).id
      end
    end
  end
end

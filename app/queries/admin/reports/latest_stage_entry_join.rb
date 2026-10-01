# frozen_string_literal: true

module Admin
  module Reports
    # LATERAL-join SQL fragment picking the single latest
    # candidate_stage_histories row entering each assignment's *current*
    # workflow stage -- i.e. "when did this assignment enter its current
    # stage." A plain LEFT JOIN on (candidate_assignment_id,
    # to_workflow_stage_id) would fan out if a stage was entered more than
    # once (a candidate can bounce back and re-advance into the same stage),
    # since candidate_stage_histories's unique index is per-destination-stage
    # across the *whole* history, not "one row total." Extracted from
    # DelayedCasesQuery (the original consumer) once a second query
    # (RecentlyUpdatedCandidatesQuery) needed the exact same join.
    module LatestStageEntryJoin
      SQL = <<~SQL.squish.freeze
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
  end
end

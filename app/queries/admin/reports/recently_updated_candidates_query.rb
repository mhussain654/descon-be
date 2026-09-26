# frozen_string_literal: true

module Admin
  module Reports
    # The most recently stage-transitioned candidate assignments (admin
    # dashboard redesign) -- "recently updated" is defined as "most recent
    # CandidateStageHistory#occurred_at," the same authoritative transition
    # timestamp DelayedCasesQuery/AverageStageDurationQuery already use, via
    # the same LatestStageEntryJoin LATERAL pattern DelayedCasesQuery
    # established (picking one row per assignment even if its current stage
    # was entered more than once).
    class RecentlyUpdatedCandidatesQuery < ApplicationQuery
      DEFAULT_LIMIT = 8
      WORKFLOW_STAGE_JOIN_SQL = 'INNER JOIN workflow_stages ON workflow_stages.id = ' \
                                'current_assignments.current_workflow_stage_id'

      def initialize(scope: Candidate.all, limit: DEFAULT_LIMIT)
        super()
        @scope = scope
        @limit = limit
      end

      def call
        joined_scope
          .order('latest_stage_entry.occurred_at DESC NULLS LAST')
          .limit(@limit)
          .pluck(
            'candidates.full_name', 'candidates.public_id',
            'current_assignments.public_id', 'current_assignments.reference_number',
            'workflow_stages.code', 'latest_stage_entry.occurred_at'
          )
          .map { |row| row_hash(row) }
      end

      private

      def row_hash(row)
        full_name, candidate_public_id, assignment_public_id, reference_number, stage_code, occurred_at = row
        {
          candidate_full_name: full_name,
          candidate_public_id: candidate_public_id,
          candidate_assignment_public_id: assignment_public_id,
          reference_number: reference_number,
          workflow_stage_code: stage_code,
          last_updated_at: occurred_at
        }
      end

      def joined_scope
        CurrentAssignmentJoin.call(scope: @scope)
                             .joins(WORKFLOW_STAGE_JOIN_SQL)
                             .joins(LatestStageEntryJoin::SQL)
      end
    end
  end
end

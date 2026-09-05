# frozen_string_literal: true

module Admin
  module Reports
    # Joins candidates to their current (most recent) assignment via the
    # same correlated-subquery pattern as
    # Admin::Candidates::CurrentAssignmentScope, without that scope's
    # `.includes` -- report/aggregation queries only ever group or count
    # columns, never render full assignment objects, so preloading every
    # association would be wasted work. Uses INNER JOIN (not LEFT): a
    # candidate with no assignment yet has nothing to report on.
    class CurrentAssignmentJoin < ApplicationQuery
      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        @scope.joins(join_sql)
      end

      private

      def join_sql
        <<~SQL.squish
          INNER JOIN candidate_assignments current_assignments ON current_assignments.id = (
            SELECT assignments.id FROM candidate_assignments assignments
            WHERE assignments.candidate_id = candidates.id
            ORDER BY assignments.created_at DESC, assignments.id DESC LIMIT 1
          )
        SQL
      end
    end
  end
end

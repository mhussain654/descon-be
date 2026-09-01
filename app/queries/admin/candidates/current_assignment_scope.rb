# frozen_string_literal: true

module Admin
  module Candidates
    class CurrentAssignmentScope < ApplicationQuery
      def initialize(scope:)
        super()
        @scope = scope
      end

      def call
        @scope.joins(join_sql).includes(candidate_assignments: %i[country project craft current_workflow_stage])
      end

      private

      def join_sql
        <<~SQL.squish
          LEFT JOIN candidate_assignments current_assignments ON current_assignments.id = (
            SELECT assignments.id FROM candidate_assignments assignments
            WHERE assignments.candidate_id = candidates.id
            ORDER BY assignments.created_at DESC, assignments.id DESC LIMIT 1
          )
        SQL
      end
    end
  end
end

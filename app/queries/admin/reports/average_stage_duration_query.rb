# frozen_string_literal: true

module Admin
  module Reports
    # Average number of days a candidate assignment spends in a workflow
    # stage before advancing, averaged across every observed stage-to-stage
    # transition (admin dashboard redesign). Each candidate_stage_histories
    # row records only the timestamp it *entered* its `to_workflow_stage`
    # (occurred_at) -- the time spent *in* a stage is the gap between an
    # assignment's consecutive occurred_at values, computed with a window
    # function rather than a self-join:
    #   occurred_at - LAG(occurred_at) OVER (
    #     PARTITION BY candidate_assignment_id ORDER BY occurred_at
    #   )
    # An assignment with only one recorded transition contributes no gap
    # (LAG is null for the first row per partition) and is correctly
    # excluded, not treated as a zero-day stage.
    class AverageStageDurationQuery < ApplicationQuery
      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      # Returns the average in days (one decimal place), or nil if no
      # assignment in scope has more than one recorded transition yet.
      def call
        average_seconds = ActiveRecord::Base.connection.select_value(sql)
        return nil if average_seconds.nil?

        (average_seconds.to_f / 1.day.to_i).round(1)
      end

      private

      def sql
        "SELECT AVG(EXTRACT(EPOCH FROM gap.duration)) FROM (#{gaps_sql}) gap WHERE gap.duration IS NOT NULL"
      end

      def gaps_sql
        <<~SQL.squish
          SELECT occurred_at - LAG(occurred_at) OVER (
            PARTITION BY candidate_assignment_id ORDER BY occurred_at
          ) AS duration
          FROM candidate_stage_histories
          WHERE candidate_assignment_id IN (#{assignment_ids_sql})
        SQL
      end

      def assignment_ids_sql
        CurrentAssignmentJoin.call(scope: @scope).select('current_assignments.id').to_sql
      end
    end
  end
end

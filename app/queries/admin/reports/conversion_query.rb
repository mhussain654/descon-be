# frozen_string_literal: true

module Admin
  module Reports
    # Docs -> Verified -> Mobilized conversion funnel (MPS-806). A
    # candidate's current stage only ever advances forward along their own
    # mobilization process, so "reached at least stage X" is reliably
    # `current process position >= X's position in that same process`; no
    # separate historical scan is needed for a simple funnel count.
    # `mobilized` counts candidates who completed their process -- its last
    # stage differs per country (e.g. Ticket Handover for KSA).
    class ConversionQuery < ApplicationQuery
      FUNNEL_STAGE_CODES = %w[documents_uploaded verified mobilized].freeze
      COMPLETED_PROCESS_CODE = 'mobilized'

      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        total = total_count
        FUNNEL_STAGE_CODES.map do |code|
          reached = reached_count(code)
          { code:, count: reached, percentage: percentage(reached, total) }
        end
      end

      private

      def base_scope
        @base_scope ||= CurrentAssignmentJoin.call(scope: @scope)
      end

      def total_count
        @total_count ||= base_scope.count
      end

      def current_process_stage_scope
        base_scope.joins(<<~SQL.squish)
          INNER JOIN mobilization_process_stages current_process_stages
            ON current_process_stages.id = current_assignments.current_mobilization_process_stage_id
        SQL
      end

      def reached_count(code)
        return completed_process_count if code == COMPLETED_PROCESS_CODE

        current_process_stage_scope
          .joins(target_stage_join_sql(code))
          .where('current_process_stages.position >= target_process_stages.position')
          .count
      end

      def completed_process_count
        base_scope.where(
          current_assignments: { current_mobilization_process_stage_id: MobilizationProcessStage.terminal.select(:id) }
        ).count
      end

      def target_stage_join_sql(code)
        ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, workflow_stage_ids.fetch(code)])
          INNER JOIN mobilization_process_stages target_process_stages
            ON target_process_stages.mobilization_process_id = current_assignments.mobilization_process_id
           AND target_process_stages.workflow_stage_id = ?
        SQL
      end

      def workflow_stage_ids
        @workflow_stage_ids ||= WorkflowStage.where(code: FUNNEL_STAGE_CODES).pluck(:code, :id).to_h
      end

      def percentage(count, total)
        return 0.0 if total.zero?

        (count.to_f / total * 100).round(1)
      end
    end
  end
end

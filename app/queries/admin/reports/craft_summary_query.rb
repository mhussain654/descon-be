# frozen_string_literal: true

module Admin
  module Reports
    # Craft/trade-wise manpower summary (MPS-804): total candidates
    # currently assigned to each craft, and how many of those have reached
    # the terminal 'mobilized' stage.
    class CraftSummaryQuery < ApplicationQuery
      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        rows = crafts.map { |craft| row_for(craft) }
        rows.sort_by { |row| -row[:total] }
      end

      private

      def row_for(craft)
        { code: craft.code, name: craft.name_for, total: total_counts.fetch(craft.id, 0),
          mobilized: mobilized_counts.fetch(craft.id, 0) }
      end

      def crafts
        @crafts ||= Craft.where(id: total_counts.keys | mobilized_counts.keys)
      end

      def base_scope
        @base_scope ||= CurrentAssignmentJoin.call(scope: @scope)
      end

      def total_counts
        @total_counts ||= base_scope.group('current_assignments.craft_id').count
      end

      def mobilized_counts
        @mobilized_counts ||= base_scope.where(current_assignments: { current_workflow_stage_id: mobilized_stage_id })
                                        .group('current_assignments.craft_id').count
      end

      def mobilized_stage_id
        @mobilized_stage_id ||= WorkflowStage.find_by!(code: 'mobilized').id
      end
    end
  end
end

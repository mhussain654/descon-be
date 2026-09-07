# frozen_string_literal: true

module Admin
  module Reports
    # Project-wise and country-wise mobilization counts (MPS-804) --
    # candidates whose current assignment has reached the terminal
    # 'mobilized' stage, broken down by country and by project.
    class MobilizationQuery < ApplicationQuery
      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        { by_country: grouped_by_country, by_project: grouped_by_project }
      end

      private

      def mobilized_scope
        @mobilized_scope ||= begin
          joined = CurrentAssignmentJoin.call(scope: @scope)
          joined.where(current_assignments: { current_workflow_stage_id: mobilized_stage_id })
        end
      end

      def mobilized_stage_id
        @mobilized_stage_id ||= WorkflowStage.find_by!(code: 'mobilized').id
      end

      def grouped_by_country
        grouped_counts(model: Country, counts: mobilized_scope.group('current_assignments.country_id').count)
      end

      def grouped_by_project
        grouped_counts(model: Project, counts: mobilized_scope.group('current_assignments.project_id').count)
      end

      def grouped_counts(model:, counts:)
        records = model.where(id: counts.keys).index_by(&:id)
        counts.filter_map { |id, count| row_for(records[id], count) }.sort_by { |row| -row[:count] }
      end

      def row_for(record, count)
        return if record.blank?

        { code: record.code, name: record.name_for, count: }
      end
    end
  end
end

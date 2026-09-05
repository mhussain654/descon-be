# frozen_string_literal: true

module Admin
  module Reports
    # Daily/weekly/monthly mobilization trend (MPS-806), sourced from
    # CandidateStageHistory -- the only place a "when did this candidate
    # reach mobilized" timestamp actually exists (the assignment's own
    # current_workflow_stage_id has no date attached).
    class TrendQuery < ApplicationQuery
      ALLOWED_GRANULARITIES = %w[daily weekly monthly].freeze
      DATE_TRUNC_UNIT = { 'daily' => 'day', 'weekly' => 'week', 'monthly' => 'month' }.freeze

      def initialize(granularity: 'monthly', from: nil, to: nil)
        super()
        raise InvalidQueryParameterError.new(field: 'granularity') unless ALLOWED_GRANULARITIES.include?(granularity)

        @granularity = granularity
        @from = from
        @to = to
      end

      def call
        counts = grouped_counts
        counts.map { |period, count| { period: period.to_date.iso8601, count: } }.sort_by { |row| row[:period] }
      end

      private

      def grouped_counts
        scope.group(Arel.sql("date_trunc('#{DATE_TRUNC_UNIT.fetch(@granularity)}', occurred_at)")).count
      end

      def scope
        relation = CandidateStageHistory.where(to_workflow_stage_id: mobilized_stage_id)
        relation = relation.where(occurred_at: @from.beginning_of_day..) if @from
        relation = relation.where(occurred_at: ..@to.end_of_day) if @to
        relation
      end

      def mobilized_stage_id
        @mobilized_stage_id ||= WorkflowStage.find_by!(code: 'mobilized').id
      end
    end
  end
end

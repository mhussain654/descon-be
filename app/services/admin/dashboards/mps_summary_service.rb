# frozen_string_literal: true

module Admin
  module Dashboards
    # Assembles the MPS dashboard (MPS-802): pipeline/status queues,
    # delayed/critical case counts, craft and mobilization (Qatar-BU)
    # summaries, and the mobilization trend.
    class MpsSummaryService < ApplicationService
      def initialize(trend_granularity: 'monthly')
        @trend_granularity = trend_granularity
      end

      def call
        {
          workflow_stage_queue: Reports::StatusSummaryQuery.call,
          delayed_cases: Reports::DelayedCasesQuery.call,
          craft_summary: Reports::CraftSummaryQuery.call,
          mobilization: Reports::MobilizationQuery.call,
          mobilization_trend: Reports::TrendQuery.call(granularity: @trend_granularity)
        }
      end
    end
  end
end

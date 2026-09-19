# frozen_string_literal: true

module Admin
  module Dashboards
    # Assembles the MPS dashboard (MPS-802): pipeline/status queues,
    # delayed/critical case counts, craft and mobilization (Qatar-BU)
    # summaries, the mobilization trend, the conversion funnel (reused
    # unchanged from the Admin dashboard -- same query, same real data), and
    # the single most recently mobilized candidate.
    class MpsSummaryService < ApplicationService
      def initialize(trend_granularity: 'monthly', params: ActionController::Parameters.new)
        @trend_granularity = trend_granularity
        @params = params
      end

      def call
        scope = filtered_scope
        {
          workflow_stage_queue: Reports::StatusSummaryQuery.call(scope:),
          delayed_cases: Reports::DelayedCasesQuery.call(scope:),
          craft_summary: Reports::CraftSummaryQuery.call(scope:),
          mobilization: Reports::MobilizationQuery.call(scope:),
          mobilization_trend: Reports::TrendQuery.call(scope:, granularity: @trend_granularity),
          conversion_funnel: Reports::ConversionQuery.call(scope:),
          latest_mobilization: Reports::LatestMobilizationQuery.call(scope:)
        }
      end

      private

      def filtered_scope
        Reports::DashboardFilterResolution.call(params: @params)
      end
    end
  end
end

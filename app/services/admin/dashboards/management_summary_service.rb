# frozen_string_literal: true

module Admin
  module Dashboards
    # Assembles the Management dashboard (MPS-803): conversion/bottleneck
    # KPIs, outcome tracking, and country/project-wise mobilization
    # insights over time.
    class ManagementSummaryService < ApplicationService
      def initialize(trend_granularity: 'monthly')
        @trend_granularity = trend_granularity
      end

      def call
        {
          conversion_funnel: Reports::ConversionQuery.call,
          outcome_tracking: Reports::OutcomeTrackingQuery.call,
          mobilization: Reports::MobilizationQuery.call,
          mobilization_trend: Reports::TrendQuery.call(granularity: @trend_granularity)
        }
      end
    end
  end
end

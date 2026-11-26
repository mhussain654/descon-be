# frozen_string_literal: true

module Admin
  module Dashboards
    # Assembles the Management dashboard (MPS-803): conversion/bottleneck
    # KPIs, outcome tracking, and country/project-wise mobilization
    # insights over time.
    class ManagementSummaryService < ApplicationService
      def initialize(trend_granularity: 'monthly', campaign_selection: nil)
        @trend_granularity = trend_granularity
        @campaign_selection = campaign_selection
      end

      def call
        scope = @campaign_selection ? @campaign_selection.apply(Candidate.all) : Candidate.all
        {
          conversion_funnel: Reports::ConversionQuery.call(scope:),
          outcome_tracking: Reports::OutcomeTrackingQuery.call(scope:),
          mobilization: Reports::MobilizationQuery.call(scope:),
          mobilization_trend: Reports::TrendQuery.call(scope:, granularity: @trend_granularity)
        }
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Management dashboard summary (MPS-803).
      class ManagementDashboardsController < ProtectedStaffController
        # Returns the management summary (KPIs, trends) for the requested
        # granularity.
        def show
          authorize :management_dashboard, policy_class: ::Admin::ManagementDashboardPolicy

          data = ::Admin::Dashboards::ManagementSummaryService.call(trend_granularity: requested_granularity)
          render_success(data:)
        end

        private

        # Reads the requested trend granularity from the query string,
        # defaulting to monthly when not supplied.
        def requested_granularity
          params[:granularity].presence || 'monthly'
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Admin
      # MPS dashboard summary (MPS-802).
      class MpsDashboardsController < ProtectedStaffController
        # Returns the MPS summary dashboard data, trended at the requested granularity.
        def show
          authorize :mps_dashboard, policy_class: ::Admin::MpsDashboardPolicy

          render_success(data: ::Admin::Dashboards::MpsSummaryService.call(trend_granularity: requested_granularity))
        end

        private

        # Reads the requested trend granularity from params, defaulting to monthly.
        def requested_granularity
          params[:granularity].presence || 'monthly'
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Admin dashboard summary (MPS-801). No natural ActiveRecord subject --
      # authorized against the `:admin_dashboard` symbol, same shape as the
      # MPS/Management dashboard controllers below.
      class DashboardsController < ProtectedStaffController
        def show
          authorize :admin_dashboard, policy_class: ::Admin::AdminDashboardPolicy

          render_success(data: ::Admin::Dashboards::AdminSummaryService.call)
        end
      end
    end
  end
end

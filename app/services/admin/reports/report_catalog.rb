# frozen_string_literal: true

module Admin
  module Reports
    # Single place mapping a report's URL key to the query object that
    # produces it (MPS-804/MPS-806) -- the reports controller and its
    # export action both go through this instead of each hardcoding the
    # list of valid report types.
    class ReportCatalog
      # Each report is narrowed by the dashboards' own filters (country,
      # project, craft and registered date range, see DashboardFilterResolution),
      # so a report can cover one import batch.
      HANDLERS = {
        'status_summary' => ->(_params, scope) { StatusSummaryQuery.call(scope:) },
        'mobilization' => ->(_params, scope) { MobilizationQuery.call(scope:) },
        'craft_summary' => ->(_params, scope) { CraftSummaryQuery.call(scope:) },
        'outcome_tracking' => ->(_params, scope) { OutcomeTrackingQuery.call(scope:) },
        'conversion' => ->(_params, scope) { ConversionQuery.call(scope:) },
        'trend' => lambda { |params, scope|
          TrendQuery.call(scope:, granularity: params[:granularity].presence || 'monthly')
        }
      }.freeze
      REPORT_TYPES = HANDLERS.keys.freeze

      def self.data_for(report_type, params: {})
        handler = HANDLERS[report_type]
        raise InvalidQueryParameterError.new(field: 'report_type') if handler.blank?

        handler.call(params, DashboardFilterResolution.call(params:))
      end
    end
  end
end

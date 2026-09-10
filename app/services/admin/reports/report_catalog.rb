# frozen_string_literal: true

module Admin
  module Reports
    # Single place mapping a report's URL key to the query object that
    # produces it (MPS-804/MPS-806) -- the reports controller and its
    # export action both go through this instead of each hardcoding the
    # list of valid report types.
    class ReportCatalog
      HANDLERS = {
        'status_summary' => ->(_params) { StatusSummaryQuery.call },
        'mobilization' => ->(_params) { MobilizationQuery.call },
        'craft_summary' => ->(_params) { CraftSummaryQuery.call },
        'outcome_tracking' => ->(_params) { OutcomeTrackingQuery.call },
        'conversion' => ->(_params) { ConversionQuery.call },
        'trend' => ->(params) { TrendQuery.call(granularity: params[:granularity].presence || 'monthly') }
      }.freeze
      REPORT_TYPES = HANDLERS.keys.freeze

      def self.data_for(report_type, params: {})
        handler = HANDLERS[report_type]
        raise InvalidQueryParameterError.new(field: 'report_type') if handler.blank?

        handler.call(params)
      end
    end
  end
end

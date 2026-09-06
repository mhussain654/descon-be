# frozen_string_literal: true

module Api
  module V1
    module Admin
      # MIS report catalogue (MPS-804/806) and per-report export (MPS-805).
      # No natural ActiveRecord subject -- authorized against the `:report`
      # symbol, same shape as the dashboard controllers.
      class ReportsController < ProtectedStaffController
        EXPORT_FORMATS = %w[csv xlsx pdf].freeze

        # Lists the report types the current staff member is permitted to
        # view, from the report catalog.
        def index
          authorize :report, policy_class: ::Admin::ReportPolicy

          report_types = policy_scope(::Admin::Reports::ReportCatalog::REPORT_TYPES,
                                      policy_scope_class: ::Admin::ReportPolicy::Scope)
          render_success(data: report_types)
        end

        # Returns the on-screen data for a single report type, filtered by
        # the request's query params.
        def show
          authorize :report, policy_class: ::Admin::ReportPolicy

          render_success(data: ::Admin::Reports::ReportCatalog.data_for(report_type, params:))
        end

        # Streams the requested report as a downloadable file in the
        # requested format (CSV, XLSX or PDF), never cached by the browser.
        def export
          authorize :report, policy_class: ::Admin::ReportPolicy

          response.set_header('Cache-Control', 'private, no-store')
          send_data export_body, filename: "#{report_type}.#{export_format}", type: export_content_type,
                                 disposition: 'attachment'
        end

        private

        # Reads the requested report type from the route params.
        def report_type
          params.expect(:report_type)
        end

        # Reads and validates the requested export format, rejecting
        # anything outside the supported CSV/XLSX/PDF set.
        def export_format
          format = params[:format].to_s
          raise InvalidQueryParameterError.new(field: 'format') unless EXPORT_FORMATS.include?(format)

          format
        end

        # Builds (and memoizes) the tabular data structure used to render
        # the export, from the same catalog data backing #show.
        def export_table
          @export_table ||= begin
            data = ::Admin::Reports::ReportCatalog.data_for(report_type, params:)
            ::Admin::Reports::ReportTable.for(report_type, data)
          end
        end

        # Renders the export table into the requested format's byte
        # content, via the matching format-specific exporter.
        def export_body
          case export_format
          when 'csv' then ::Admin::Reports::CsvExport.call(**export_table)
          when 'xlsx' then ::Admin::Reports::XlsxExport.call(**export_table)
          when 'pdf' then ::Admin::Reports::PdfExport.call(**export_table)
          end
        end

        # Maps the requested export format to its HTTP content type.
        def export_content_type
          {
            'csv' => 'text/csv; charset=utf-8',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'pdf' => 'application/pdf'
          }.fetch(export_format)
        end
      end
    end
  end
end

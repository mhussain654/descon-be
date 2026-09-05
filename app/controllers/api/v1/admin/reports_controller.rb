# frozen_string_literal: true

module Api
  module V1
    module Admin
      # MIS report catalogue (MPS-804/806) and per-report export (MPS-805).
      # No natural ActiveRecord subject -- authorized against the `:report`
      # symbol, same shape as the dashboard controllers.
      class ReportsController < ProtectedStaffController
        EXPORT_FORMATS = %w[csv xlsx pdf].freeze

        def index
          authorize :report, policy_class: ::Admin::ReportPolicy

          report_types = policy_scope(::Admin::Reports::ReportCatalog::REPORT_TYPES,
                                      policy_scope_class: ::Admin::ReportPolicy::Scope)
          render_success(data: report_types)
        end

        def show
          authorize :report, policy_class: ::Admin::ReportPolicy

          render_success(data: ::Admin::Reports::ReportCatalog.data_for(report_type, params:))
        end

        def export
          authorize :report, policy_class: ::Admin::ReportPolicy

          response.set_header('Cache-Control', 'private, no-store')
          send_data export_body, filename: "#{report_type}.#{export_format}", type: export_content_type,
                                 disposition: 'attachment'
        end

        private

        def report_type
          params.expect(:report_type)
        end

        def export_format
          format = params[:format].to_s
          raise InvalidQueryParameterError.new(field: 'format') unless EXPORT_FORMATS.include?(format)

          format
        end

        def export_table
          @export_table ||= begin
            data = ::Admin::Reports::ReportCatalog.data_for(report_type, params:)
            ::Admin::Reports::ReportTable.for(report_type, data)
          end
        end

        def export_body
          case export_format
          when 'csv' then ::Admin::Reports::CsvExport.call(**export_table)
          when 'xlsx' then ::Admin::Reports::XlsxExport.call(**export_table)
          when 'pdf' then ::Admin::Reports::PdfExport.call(**export_table)
          end
        end

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

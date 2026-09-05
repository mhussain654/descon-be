# frozen_string_literal: true

module Admin
  module Reports
    # Flattens one report's (heterogeneously shaped) query result into a
    # single {headers:, rows:} table for CSV/XLSX/PDF export (MPS-805).
    # Every report type produced by ReportCatalog is handled explicitly --
    # there is no generic fallback, so a new report type must add its own
    # table shape here deliberately rather than exporting something wrong.
    class ReportTable
      def self.for(report_type, data)
        new(report_type, data).call
      end

      def initialize(report_type, data)
        @report_type = report_type
        @data = data
      end

      def call
        case @report_type
        when 'status_summary' then array_table(%w[code position count])
        when 'craft_summary' then array_table(%w[code name total mobilized])
        when 'conversion' then array_table(%w[code count percentage])
        when 'trend' then array_table(%w[period count])
        when 'mobilization' then mobilization_table
        when 'outcome_tracking' then outcome_tracking_table
        end
      end

      private

      def array_table(headers)
        { headers:, rows: @data.map { |row| headers.map { |header| row.fetch(header.to_sym) } } }
      end

      def mobilization_table
        headers = %w[dimension code name count]
        by_country = @data.fetch(:by_country).map do |row|
          ['country', row.fetch(:code), row.fetch(:name), row.fetch(:count)]
        end
        by_project = @data.fetch(:by_project).map do |row|
          ['project', row.fetch(:code), row.fetch(:name), row.fetch(:count)]
        end
        { headers:, rows: by_country + by_project }
      end

      def outcome_tracking_table
        headers = @data.keys.map(&:to_s)
        { headers:, rows: [headers.map { |header| @data.fetch(header.to_sym) }] }
      end
    end
  end
end

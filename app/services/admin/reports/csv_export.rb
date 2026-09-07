# frozen_string_literal: true

require 'csv'

module Admin
  module Reports
    class CsvExport
      def self.call(headers:, rows:)
        CSV.generate(encoding: Encoding::UTF_8, row_sep: "\r\n") do |csv|
          csv << headers
          rows.each { |row| csv << row }
        end
      end
    end
  end
end

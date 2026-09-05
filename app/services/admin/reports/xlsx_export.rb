# frozen_string_literal: true

module Admin
  module Reports
    class XlsxExport
      def self.call(headers:, rows:)
        package = Axlsx::Package.new
        package.workbook.add_worksheet(name: 'Report') do |sheet|
          sheet.add_row headers, style: sheet.styles.add_style(b: true)
          rows.each { |row| sheet.add_row row }
        end
        package.to_stream.read
      end
    end
  end
end

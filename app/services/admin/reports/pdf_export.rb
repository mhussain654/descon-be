# frozen_string_literal: true

module Admin
  module Reports
    class PdfExport
      def self.call(headers:, rows:)
        document = Prawn::Document.new(page_layout: :landscape)
        document.table([headers.map(&:to_s)] + rows.map { |row| row.map(&:to_s) }, header: true)
        document.render
      end
    end
  end
end

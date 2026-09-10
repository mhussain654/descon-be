# frozen_string_literal: true

module Admin
  module Reports
    # Neutralizes spreadsheet-formula injection (a string cell starting with
    # =, +, -, @, a tab or a carriage return can be interpreted as a formula
    # by Excel/Sheets when the export is opened) for CsvExport/XlsxExport.
    # Only String values are ever touched -- a real Integer/Float/Date cell
    # is returned unchanged so it stays a typed, sortable value in the
    # exported file rather than becoming a text string.
    module FormulaInjectionGuard
      DANGEROUS_LEADING_CHARACTERS = ['=', '+', '-', '@', "\t", "\r"].freeze

      def self.sanitize_row(row)
        row.map { |value| sanitize_cell(value) }
      end

      def self.sanitize_cell(value)
        return value unless value.is_a?(String)
        return value unless DANGEROUS_LEADING_CHARACTERS.any? { |char| value.start_with?(char) }

        "'#{value}"
      end
    end
  end
end

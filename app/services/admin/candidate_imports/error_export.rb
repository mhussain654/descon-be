# frozen_string_literal: true

require 'csv'

module Admin
  module CandidateImports
    class ErrorExport
      def initialize(batch)
        @batch = batch
      end

      def to_csv
        CSV.generate(encoding: Encoding::UTF_8, row_sep: "\r\n") do |csv|
          csv << %w[row_number status field code message]
          @batch.row_results.where(status: %w[rejected skipped]).order(:row_number).find_each do |row|
            csv << [row.row_number, row.status, row.error_field, row.error_code, localized_message(row.error_code)]
          end
        end
      end

      private

      def localized_message(error_code)
        return nil if error_code.blank?

        I18n.t("api.candidate_imports.row_errors.#{error_code}")
      end
    end
  end
end

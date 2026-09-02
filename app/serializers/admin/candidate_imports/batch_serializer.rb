# frozen_string_literal: true

module Admin
  module CandidateImports
    class BatchSerializer
      def initialize(batch, include_rows: false)
        @batch = batch
        @include_rows = include_rows
      end

      def as_json(*)
        attributes = {
          id: @batch.public_id, status: @batch.status, source_filename: @batch.source_filename,
          template_version: @batch.template_version, total_rows: @batch.total_rows,
          accepted_rows: @batch.accepted_rows, rejected_rows: @batch.rejected_rows,
          skipped_rows: @batch.skipped_rows, committed_rows: @batch.committed_rows,
          imported_rows: @batch.imported_rows, error_code: @batch.error_code,
          expires_at: @batch.expires_at&.utc&.iso8601, processed_at: @batch.processed_at&.utc&.iso8601,
          failed_at: @batch.failed_at&.utc&.iso8601, created_at: @batch.created_at.utc.iso8601
        }
        return attributes unless @include_rows

        attributes.merge(row_results: @batch.row_results.sort_by(&:row_number).map { |row| serialize_row(row) })
      end

      private

      def serialize_row(row)
        {
          row_number: row.row_number, status: row.status, error_field: row.error_field,
          error_code: row.error_code, message: localized_message(row.error_code)
        }.compact
      end

      def localized_message(error_code)
        return if error_code.blank?

        I18n.t("api.candidate_imports.row_errors.#{error_code}")
      end
    end
  end
end

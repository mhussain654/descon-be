# frozen_string_literal: true

module Admin
  module CandidateImports
    class BatchSerializer
      def initialize(batch, include_rows: false)
        @batch = batch
        @include_rows = include_rows
      end

      def as_json(*)
        return attributes unless @include_rows

        attributes.merge(row_results: serialized_rows)
      end

      private

      def attributes
        counts.merge(timestamps)
      end

      def counts
        {
          id: @batch.public_id, status: @batch.status, source_filename: @batch.source_filename,
          template_version: @batch.template_version, total_rows: @batch.total_rows,
          accepted_rows: @batch.accepted_rows, rejected_rows: @batch.rejected_rows,
          skipped_rows: @batch.skipped_rows, committed_rows: @batch.committed_rows,
          imported_rows: @batch.imported_rows, error_code: @batch.error_code
        }
      end

      def timestamps
        {
          expires_at: timestamp(@batch.expires_at), processed_at: timestamp(@batch.processed_at),
          failed_at: timestamp(@batch.failed_at), enqueued_at: timestamp(@batch.enqueued_at),
          created_at: timestamp(@batch.created_at)
        }
      end

      def serialized_rows = @batch.row_results.sort_by(&:row_number).map { |row| serialize_row(row) }

      def timestamp(value) = value&.utc&.iso8601

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

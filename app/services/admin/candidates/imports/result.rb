# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class Result
        RowPlan = Data.define(
          :row_number,
          :candidate_attributes,
          :assignment_attributes,
          :errors,
          :blank,
          :source_values
        ) do
          # source_values: the row's raw CSV cells, used only to show the
          # rejected cell alongside a row error (see RejectedValue).
          def initialize(source_values: {}, **) = super
          def blank? = blank
          def invalid? = errors.any?
          def cnic = candidate_attributes.fetch(:cnic)
          def passport_number = candidate_attributes[:passport_number]
          def mobile_number = candidate_attributes[:mobile_number]
          def reference_number = assignment_attributes.fetch(:reference_number)
        end

        def initialize(total_rows:)
          @total_rows = total_rows
          @successful_rows = 0
          @failed_rows = 0
          @skipped_rows = 0
          @errors = []
          @persistable_rows = []
        end

        attr_reader :persistable_rows

        def schedule(row_plan)
          @persistable_rows << row_plan
        end

        def record_success
          @successful_rows += 1
        end

        def record_failed(row_number:, errors:, source_values: {})
          @failed_rows += 1
          append_errors(row_number:, errors:, source_values:)
        end

        def record_skipped(row_number:, field:, code:, source_values: {})
          @skipped_rows += 1
          append_errors(row_number:, errors: [{ field:, code: }], source_values:)
        end

        def summary
          {
            successful_rows: @successful_rows,
            failed_rows: @failed_rows,
            skipped_rows: @skipped_rows,
            total_rows: @total_rows
          }
        end

        def to_h
          summary.merge(errors: @errors)
        end

        private

        def append_errors(row_number:, errors:, source_values:)
          errors.each do |error|
            field = error.fetch(:field)
            @errors << {
              row: row_number,
              field:,
              code: error.fetch(:code),
              value: RejectedValue.call(field:, source_values:),
              message: I18n.t("api.candidate_imports.row_errors.#{error.fetch(:code)}")
            }
          end
        end
      end
    end
  end
end

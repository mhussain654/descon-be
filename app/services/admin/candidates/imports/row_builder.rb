# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class RowBuilder
        def initialize(actor:)
          @candidate_attributes_builder = CandidateAttributesBuilder.new(actor:)
          @assignment_attributes_builder = AssignmentAttributesBuilder.new(actor:)
        end

        def call(row:, row_number:)
          attributes = normalized_row_attributes(row)
          return blank_row(row_number:) if blank_row?(attributes)

          build_row_plan(attributes:, row_number:)
        end

        private

        def normalized_row_attributes(row)
          CsvFileParser::REQUIRED_HEADERS.index_with { |header| row[header].to_s.strip }
        end

        def blank_row?(attributes)
          attributes.values.all?(&:blank?)
        end

        def blank_row(row_number:)
          Result::RowPlan.new(
            row_number:,
            candidate_attributes: {},
            assignment_attributes: {},
            errors: [],
            blank: true
          )
        end

        def build_row_plan(attributes:, row_number:)
          row_errors = []
          candidate_attributes = @candidate_attributes_builder.call(attributes:, row_errors:)
          assignment_attributes = @assignment_attributes_builder.call(attributes:, row_errors:)

          Result::RowPlan.new(
            row_number:,
            candidate_attributes:,
            assignment_attributes:,
            errors: row_errors,
            blank: false
          )
        end
      end
    end
  end
end

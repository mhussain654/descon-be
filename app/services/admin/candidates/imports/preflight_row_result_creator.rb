# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class PreflightRowResultCreator < ApplicationService
        def initialize(batch:, rows:, errors:)
          @batch = batch
          @rows = rows
          @errors = errors
        end

        def call
          accepted_rows.each { |attributes| CandidateImportRowResult.create!(attributes) }
          rejected_rows.each { |attributes| CandidateImportRowResult.create!(attributes) }
        end

        private

        def accepted_rows
          @rows.map do |row|
            { candidate_import_batch: @batch, row_number: row.fetch('row_number'), status: 'accepted' }
          end
        end

        def rejected_rows
          @errors.map do |error|
            {
              candidate_import_batch: @batch, row_number: error.fetch(:row), status: 'rejected',
              error_field: error.fetch(:field), error_code: error.fetch(:code)
            }
          end
        end
      end
    end
  end
end

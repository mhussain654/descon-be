# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class DuplicateTracker
        def initialize
          @seen_cnics = Set.new
          @seen_reference_numbers = Set.new
        end

        def register(row_plan)
          return { field: 'cnic', code: 'duplicate_cnic_in_file' } if @seen_cnics.include?(row_plan.cnic)
          return duplicate_reference_number_error if @seen_reference_numbers.include?(row_plan.reference_number)

          @seen_cnics << row_plan.cnic
          @seen_reference_numbers << row_plan.reference_number
          nil
        end

        private

        def duplicate_reference_number_error
          { field: 'reference_number', code: 'duplicate_reference_number_in_file' }
        end
      end
    end
  end
end

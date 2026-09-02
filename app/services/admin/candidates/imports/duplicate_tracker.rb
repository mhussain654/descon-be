# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class DuplicateTracker
        def initialize
          @seen_cnics = Set.new
          @seen_passports = Set.new
          @seen_mobile_numbers = Set.new
          @seen_reference_numbers = Set.new
        end

        def register(row_plan)
          duplicate = duplicate_for(row_plan)
          return duplicate if duplicate

          remember(row_plan)
          nil
        end

        private

        def duplicate_for(row_plan)
          return { field: 'cnic', code: 'duplicate_cnic_in_file' } if @seen_cnics.include?(row_plan.cnic)
          return { field: 'passport_number', code: 'duplicate_passport_in_file' } if duplicate_passport?(row_plan)
          if @seen_mobile_numbers.include?(row_plan.mobile_number)
            return { field: 'mobile_number',
                     code: 'duplicate_mobile_number_in_file' }
          end
          duplicate_reference_number_error if @seen_reference_numbers.include?(row_plan.reference_number)
        end

        def duplicate_passport?(row_plan)
          row_plan.passport_number.present? && @seen_passports.include?(row_plan.passport_number)
        end

        def remember(row_plan)
          @seen_cnics << row_plan.cnic
          @seen_passports << row_plan.passport_number if row_plan.passport_number.present?
          @seen_mobile_numbers << row_plan.mobile_number
          @seen_reference_numbers << row_plan.reference_number
          nil
        end

        def duplicate_reference_number_error
          { field: 'reference_number', code: 'duplicate_reference_number_in_file' }
        end
      end
    end
  end
end

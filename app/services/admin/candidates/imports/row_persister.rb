# frozen_string_literal: true

module Admin
  module Candidates
    module Imports
      class RowPersister
        def call(row_plan:, result:)
          return handle_duplicate(row_plan:, result:) if duplicate_row?(row_plan)

          persist_row!(row_plan)
          result.record_success
        rescue ActiveRecord::RecordInvalid
          result.record_failed(
            row_number: row_plan.row_number,
            errors: [{ field: 'row', code: 'validation_failed' }]
          )
        rescue ActiveRecord::RecordNotUnique
          result.record_skipped(row_number: row_plan.row_number, field: 'row', code: 'duplicate_row')
        end

        private

        def duplicate_row?(row_plan)
          ::Candidate.exists?(cnic: row_plan.cnic) ||
            ::CandidateAssignment.exists?(reference_number: row_plan.reference_number)
        end

        def handle_duplicate(row_plan:, result:)
          return record_duplicate_candidate(row_plan:, result:) if ::Candidate.exists?(cnic: row_plan.cnic)

          record_duplicate_reference_number(row_plan:, result:)
        end

        def record_duplicate_candidate(row_plan:, result:)
          result.record_skipped(row_number: row_plan.row_number, field: 'cnic', code: 'duplicate_candidate')
        end

        def record_duplicate_reference_number(row_plan:, result:)
          result.record_skipped(
            row_number: row_plan.row_number,
            field: 'reference_number',
            code: 'duplicate_reference_number'
          )
        end

        def create_candidate!(row_plan)
          candidate = ::Candidate.create!(row_plan.candidate_attributes)
          candidate.candidate_assignments.create!(row_plan.assignment_attributes)
        end

        def persist_row!(row_plan)
          ActiveRecord::Base.transaction(requires_new: true) do
            create_candidate!(row_plan)
          end
        end
      end
    end
  end
end

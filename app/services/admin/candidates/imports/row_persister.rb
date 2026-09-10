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
          record_failed(row_plan:, result:, field: 'row', code: 'validation_failed')
        rescue ActiveRecord::RecordNotUnique
          result.record_skipped(row_number: row_plan.row_number, field: 'row', code: 'duplicate_row')
        rescue WorkflowTransitionPrerequisiteError, InvalidWorkflowTransitionError
          # Without this rescue, either error escapes persist_row!'s
          # savepoint (requires_new: true only isolates the DB writes, not
          # Ruby exceptions) and propagates out through
          # ImportService#persist_import!'s single outer transaction --
          # silently rolling back every candidate already committed earlier
          # in the same CSV upload, and turning one bad row into a 500
          # instead of the partial-success response this row-by-row design
          # exists to produce.
          record_failed(row_plan:, result:, field: 'workflow_stage_code', code: 'workflow_transition_failed')
        end

        private

        def record_failed(row_plan:, result:, field:, code:)
          result.record_failed(row_number: row_plan.row_number, errors: [{ field:, code: }])
        end

        def duplicate_row?(row_plan)
          ::Candidate.exists?(cnic: row_plan.cnic) ||
            (row_plan.passport_number.present? && ::Candidate.exists?(passport_number: row_plan.passport_number)) ||
            ::Candidate.exists?(mobile_number: row_plan.mobile_number) ||
            ::CandidateAssignment.exists?(reference_number: row_plan.reference_number)
        end

        def handle_duplicate(row_plan:, result:)
          return record_duplicate_candidate(row_plan:, result:) if ::Candidate.exists?(cnic: row_plan.cnic)
          if row_plan.passport_number.present? && ::Candidate.exists?(passport_number: row_plan.passport_number)
            return result.record_skipped(row_number: row_plan.row_number, field: 'passport_number',
                                         code: 'duplicate_passport')
          end
          if ::Candidate.exists?(mobile_number: row_plan.mobile_number)
            return result.record_skipped(row_number: row_plan.row_number, field: 'mobile_number',
                                         code: 'duplicate_mobile_number')
          end

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
          assignment = candidate.candidate_assignments.create!(row_plan.assignment_attributes)
          advance_workflow!(candidate:, assignment:)
        end

        def persist_row!(row_plan)
          ActiveRecord::Base.transaction(requires_new: true) do
            create_candidate!(row_plan)
          end
        end

        # A CSV row can set `workflow_stage_code` to any active stage, not
        # just `registered` (e.g. importing candidates already mid-pipeline
        # from a legacy system). AutomaticTransitionService can't record
        # that directly -- it only knows how to step forward one
        # sequentially-validated stage at a time starting from `registered`,
        # and would reject a jump straight to a later stage. For any other
        # starting stage, record the landing directly instead, so history-
        # sourced reports (e.g. Admin::Reports::TrendQuery) don't silently
        # diverge from stage-sourced reports for these candidates.
        def advance_workflow!(candidate:, assignment:)
          if assignment.current_workflow_stage.code == 'registered'
            ::CandidateWorkflows::AutomaticTransitionService.call(
              candidate:,
              event: :assignment_created,
              actor: assignment.created_by,
              request_id: "candidate-assignment-#{assignment.public_id}"
            )
          else
            record_direct_import_stage!(assignment:)
          end
        end

        def record_direct_import_stage!(assignment:)
          ::CandidateStageHistory.create!(
            candidate_assignment: assignment,
            from_workflow_stage: nil,
            to_workflow_stage: assignment.current_workflow_stage,
            actor: assignment.created_by,
            occurred_at: assignment.created_at,
            reason_code: 'csv_import',
            metadata: {}
          )
        end
      end
    end
  end
end

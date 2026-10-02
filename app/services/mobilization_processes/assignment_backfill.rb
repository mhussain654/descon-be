# frozen_string_literal: true

module MobilizationProcesses
  # One-off: attaches assignments created before mobilization processes
  # existed to their country's active process, positioned at their current
  # stage. An assignment whose current stage isn't part of that process is
  # left untouched and reported back so staff can decide (a dev database can
  # simply be reset instead).
  class AssignmentBackfill < ApplicationService
    Result = Data.define(:linked_count, :unmatched_reference_numbers)

    def call
      linked_count = 0
      unmatched = []
      CandidateAssignment.where(mobilization_process_id: nil).includes(:country, :current_workflow_stage)
                         .find_each do |assignment|
        linked?(assignment) ? linked_count += 1 : unmatched << assignment.reference_number
      end
      Result.new(linked_count:, unmatched_reference_numbers: unmatched)
    end

    private

    def linked?(assignment)
      process = MobilizationProcess.resolve_for(assignment.country)
      process_stage = process&.stage_for(assignment.current_workflow_stage)
      return false if process_stage.blank?

      # update_columns: the assignment's own timestamps and callbacks must not
      # move -- this only fills in links that should always have existed.
      assignment.update_columns(mobilization_process_id: process.id, # rubocop:disable Rails/SkipsModelValidations
                                current_mobilization_process_stage_id: process_stage.id)
      true
    end
  end
end

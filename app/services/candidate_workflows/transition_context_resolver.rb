# frozen_string_literal: true

module CandidateWorkflows
  # Locks the candidate and their current assignment and resolves both ends of
  # the transition against that assignment's own mobilization process: a stage
  # code that exists in the catalog but not in this candidate's process (e.g. a
  # QVC stage for a KSA candidate) is rejected here, before any other check.
  class TransitionContextResolver < ApplicationService
    def initialize(candidate:, to_stage_code:)
      @candidate = candidate
      @to_stage_code = to_stage_code
    end

    def call
      candidate = locked_candidate
      assignment = locked_assignment(candidate)
      { candidate:, assignment:, **process_context(assignment) }
    end

    private

    def process_context(assignment)
      destination_stage = destination_stage(assignment)
      {
        mobilization_process: assignment.mobilization_process,
        current_stage: assignment.current_workflow_stage,
        current_process_stage: assignment.current_mobilization_process_stage,
        destination_stage:,
        destination_process_stage: assignment.mobilization_process.stage_for(destination_stage)
      }
    end

    def locked_candidate
      candidate = Candidate.lock.find(@candidate.id)
      raise InactiveAccountError unless candidate.active?

      candidate
    end

    def locked_assignment(candidate)
      assignment_id = candidate.current_assignment&.id
      raise NoCurrentAssignmentError if assignment_id.blank?

      CandidateAssignment.includes(:current_workflow_stage, :current_mobilization_process_stage,
                                   mobilization_process: :stages)
                         .lock.find(assignment_id)
    end

    def destination_stage(assignment)
      stage = WorkflowStage.find_by(code: @to_stage_code)
      return stage if stage && assignment.mobilization_process.stage_for(stage)

      raise InvalidWorkflowTransitionError.new(
        field: 'candidate_workflow_transition.to_stage_code',
        details: { to_stage_code: @to_stage_code, mobilization_process_code: assignment.mobilization_process.code }
      )
    end
  end
end

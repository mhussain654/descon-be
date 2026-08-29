# frozen_string_literal: true

module CandidateWorkflows
  class TransitionContextResolver < ApplicationService
    def initialize(candidate:, to_stage_code:)
      @candidate = candidate
      @to_stage_code = to_stage_code
    end

    def call
      candidate = locked_candidate
      assignment = locked_assignment(candidate)
      {
        candidate:,
        assignment:,
        current_stage: assignment.current_workflow_stage,
        destination_stage: destination_stage
      }
    end

    private

    def locked_candidate
      candidate = Candidate.lock.find(@candidate.id)
      raise InactiveAccountError unless candidate.active?

      candidate
    end

    def locked_assignment(candidate)
      assignment_id = candidate.current_assignment&.id
      raise NoCurrentAssignmentError if assignment_id.blank?

      CandidateAssignment.includes(:current_workflow_stage).lock.find(assignment_id)
    end

    def destination_stage
      stage = WorkflowStage.find_by(code: @to_stage_code)
      raise InvalidWorkflowTransitionError.new(field: 'candidate_workflow_transition.to_stage_code') if stage.blank?

      stage
    end
  end
end

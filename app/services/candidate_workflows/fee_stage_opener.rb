# frozen_string_literal: true

module CandidateWorkflows
  # Moves a candidate into the fee stage as soon as the stage before it is completed (the medical
  # outcome, or the visa case being prepared), so nobody has to press a separate "Fee Pending"
  # step before the candidate can pay. It only acts when the fee stage is the very next stage in the
  # candidate's own process and its prerequisites are met (verified documents); otherwise the
  # candidate stays where they are and an admin can still move them on by hand.
  class FeeStageOpener < ApplicationService
    FEE_STAGE_CODE = 'fee_pending'
    REASON_CODE = 'auto_fee_stage_opened'

    def initialize(actor:, candidate:, request_id:)
      @actor = actor
      @candidate = candidate
      @request_id = request_id
    end

    def call
      return unless fee_stage_next? && fee_stage_allowed?

      open_fee_stage
    end

    private

    def assignment
      @assignment ||= @candidate.current_assignment&.reload
    end

    def fee_stage
      @fee_stage ||= WorkflowStage.find_by!(code: FEE_STAGE_CODE)
    end

    def fee_stage_next?
      assignment.present? && assignment.next_process_stage&.workflow_stage_id == fee_stage.id
    end

    def fee_stage_allowed?
      TransitionService.transition_prerequisite_result(
        candidate: @candidate, assignment:, destination_stage: fee_stage
      ).allowed
    end

    # A concurrent writer may already have moved the candidate on; that is fine, nothing is left to open.
    def open_fee_stage
      TransitionService.call(
        actor: @actor, candidate: @candidate, to_stage_code: FEE_STAGE_CODE,
        request_id: "#{@request_id}:#{FEE_STAGE_CODE}", reason_code: REASON_CODE, validate_permissions: false
      )
    rescue InvalidWorkflowTransitionError, WorkflowTransitionPrerequisiteError
      nil
    end
  end
end

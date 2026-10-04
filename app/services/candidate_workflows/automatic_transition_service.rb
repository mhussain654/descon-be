# frozen_string_literal: true

module CandidateWorkflows
  # Advances a candidate, one step at a time along their own process, up to the
  # stage an event implies (stopping early at any step whose prerequisites
  # aren't met). An event whose target isn't in the candidate's process -- or
  # is already behind them -- does nothing.
  class AutomaticTransitionService < ApplicationService
    EVENT_TARGETS = {
      assignment_created: 'documents_pending',
      documents_uploaded: 'documents_uploaded',
      documents_submitted: 'under_verification',
      documents_reviewed: 'verified'
    }.freeze

    def initialize(candidate:, event:, actor: nil, request_id: nil)
      @candidate = candidate
      @event = event.to_sym
      @actor = actor
      @request_id = request_id
    end

    def call
      return if assignment.blank? || !@candidate.active?
      return assignment.current_workflow_stage if target_process_stage.blank?

      advance_one_stage! while current_position < target_process_stage.position && advanceable_next_stage
      assignment.current_workflow_stage
    end

    private

    def assignment
      @assignment ||= @candidate.current_assignment
    end

    def current_position
      assignment.current_mobilization_process_stage.position
    end

    # The next stage in the candidate's process, if its prerequisites are met.
    def advanceable_next_stage
      next_process_stage = assignment.next_process_stage
      return if next_process_stage.blank?

      next_stage = WorkflowStage.find(next_process_stage.workflow_stage_id)
      next_stage if next_stage_allowed?(next_stage)
    end

    def advance_one_stage!
      next_process_stage = assignment.next_process_stage
      transition_to_next_stage!(WorkflowStage.find(next_process_stage.workflow_stage_id), next_process_stage)
      assignment.reload
    end

    def target_process_stage
      return @target_process_stage if defined?(@target_process_stage)

      @target_process_stage = assignment.mobilization_process.stage_with_code(EVENT_TARGETS.fetch(@event))
    end

    def next_stage_allowed?(next_stage)
      TransitionService.transition_prerequisite_result(
        candidate: @candidate,
        assignment:,
        destination_stage: next_stage
      ).allowed
    end

    # A concurrent writer may have already moved the candidate past this step;
    # that's fine -- only re-raise if they're still behind it.
    def transition_to_next_stage!(next_stage, next_process_stage)
      TransitionService.call(actor: @actor, candidate: @candidate, to_stage_code: next_stage.code,
                             request_id: transition_request_id, reason_code:, validate_permissions: false)
    rescue InvalidWorkflowTransitionError
      assignment.reload
      raise unless current_position >= next_process_stage.position
    end

    def transition_request_id
      @request_id.presence || "workflow-auto-#{@event}-#{assignment.public_id}"
    end

    def reason_code
      "auto_#{@event}"
    end
  end
end

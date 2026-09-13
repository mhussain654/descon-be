# frozen_string_literal: true

module AiCalls
  # Places the automatically-triggered call for one workflow-stage
  # transition, if that stage has an active WorkflowStageCallScript --
  # called by AiCalls::TriggerWorkflowStageCallJob, enqueued from
  # CandidateWorkflows::TransitionSideEffectRecorder (never called inline
  # inside the transition's own DB transaction).
  #
  # Idempotency here is permanent, not a time window (see the plan's
  # "Client clarifications" #6): at most one call per
  # (candidate_assignment, workflow_stage_code), ever -- re-entering the
  # same stage never re-triggers a call. This is on top of, not instead of,
  # AiCalls::OutboundCallGuard's checks (kill switch, calling hours, daily
  # cap) enforced by the shared TriggerOutboundCallService.
  class TriggerWorkflowStageCallService < ApplicationService
    def initialize(candidate_assignment_id:, workflow_stage_code:, request_id:,
                   configuration: AiCalls::Configuration.new)
      @candidate_assignment_id = candidate_assignment_id
      @workflow_stage_code = workflow_stage_code
      @request_id = request_id
      @configuration = configuration
    end

    def call
      script = WorkflowStageCallScript.active.find_by(workflow_stage_code: @workflow_stage_code)
      return if script.blank?

      ActiveRecord::Base.transaction { execute_trigger(script) }
    end

    private

    def execute_trigger(script)
      assignment = CandidateAssignment.lock.find(@candidate_assignment_id)
      return if already_called?(assignment)

      candidate = Candidate.find(assignment.candidate_id)
      return unless candidate.active?

      TriggerOutboundCallService.new(
        candidate:, plan: OutboundCallPlan.for_workflow_stage(script), request_id: @request_id,
        configuration: @configuration
      ).call
    end

    def already_called?(assignment)
      CandidateAiCall.exists?(candidate_assignment_id: assignment.id, call_reason: 'workflow_stage_notification',
                              workflow_stage_code: @workflow_stage_code)
    end
  end
end

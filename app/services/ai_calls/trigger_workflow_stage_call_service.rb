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
    # The job retrying AiCallOutsideCallingHoursError/AiCallDailyLimitReachedError
    # (see AiCalls::TriggerWorkflowStageCallJob) can legitimately delay
    # execution by roughly a day. By then the destination stage's content
    # (e.g. "your documents need review") may no longer describe the
    # candidate's situation at all -- past this window the notification is
    # considered stale and is dropped rather than placed late.
    NOTIFICATION_WINDOW = 24.hours

    def initialize(candidate_assignment_id:, workflow_stage_code:, request_id:, transitioned_at: Time.current,
                   configuration: AiCalls::Configuration.new)
      @candidate_assignment_id = candidate_assignment_id
      @workflow_stage_code = workflow_stage_code
      @request_id = request_id
      @transitioned_at = transitioned_at
      @configuration = configuration
    end

    def call
      return if @transitioned_at <= Time.current - NOTIFICATION_WINDOW
      return unless AppFeatureSetting.enabled?(:automatic_calls)

      script = WorkflowStageCallScript.active.find_by(workflow_stage_code: @workflow_stage_code)
      return if script.blank?
      return if skip_for_missing_voice?(script)

      ActiveRecord::Base.transaction { execute_trigger(script) }
    end

    private

    # RoboCall plays a fixed voice, so a stage with no voice set up has
    # nothing to play: skipped, never an error.
    def skip_for_missing_voice?(script)
      @configuration.robocall? && script.voice_id.blank?
    end

    def execute_trigger(script)
      assignment = CandidateAssignment.lock.find(@candidate_assignment_id)
      return if already_called?(assignment)
      return unless still_at_relevant_stage?(assignment)
      return if unfit_medical_result?(assignment)

      candidate = Candidate.find(assignment.candidate_id)
      return unless candidate.active?

      TriggerOutboundCallService.new(
        candidate:, plan: OutboundCallPlan.for_workflow_stage(script), request_id: @request_id,
        configuration: @configuration
      ).call
    end

    # The candidate may have progressed through further stages by the time
    # a retried job finally executes (e.g. the daily outbound-call cap or
    # calling-hours retry can delay this by up to ~30 hours) -- placing a
    # call whose content describes a stage the assignment has already moved
    # past would be actively misleading, so this is a no-op rather than a
    # late call.
    def still_at_relevant_stage?(assignment)
      assignment.current_workflow_stage&.code == @workflow_stage_code
    end

    # A call set on a medical-result stage announces good news ("your report is
    # in, pay the fee"), so it is placed only for a fit result. An unfit
    # candidate is held at that stage and hears nothing automatically.
    def unfit_medical_result?(assignment)
      return false unless MobilizationProcesses::Definitions.action_type_for(@workflow_stage_code) == 'medical_outcome'

      latest = assignment.candidate_medical_results.latest_first.first
      latest.present? && !latest.fit?
    end

    def already_called?(assignment)
      CandidateAiCall.exists?(candidate_assignment_id: assignment.id, call_reason: 'workflow_stage_notification',
                              workflow_stage_code: @workflow_stage_code)
    end
  end
end

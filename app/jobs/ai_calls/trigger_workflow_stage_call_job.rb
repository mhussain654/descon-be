# frozen_string_literal: true

module AiCalls
  # Enqueued by CandidateWorkflows::TransitionSideEffectRecorder on every
  # workflow transition (a no-op if the destination stage has no active
  # script) -- never calls ElevenLabs inline inside the transition request.
  #
  # Retries on the two operational-safety conditions that are expected to
  # clear on their own (outside calling hours; daily cap reached, which
  # resets the next day) rather than dropping the call entirely. Does not
  # retry AiCallOutboundDisabledError -- if the feature is off, retrying
  # blindly won't help, and it should be visible as a failed job.
  class TriggerWorkflowStageCallJob < ApplicationJob
    queue_as :default

    retry_on AiCallOutsideCallingHoursError, wait: 30.minutes, attempts: 48
    retry_on AiCallDailyLimitReachedError, wait: 1.hour, attempts: 30

    def perform(candidate_assignment_id:, workflow_stage_code:, request_id:)
      TriggerWorkflowStageCallService.new(candidate_assignment_id:, workflow_stage_code:, request_id:).call
    end
  end
end

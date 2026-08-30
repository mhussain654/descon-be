# frozen_string_literal: true

module CandidateWorkflows
  class ExpectedStageValidator < ApplicationService
    def initialize(current_stage:, expected_current_stage_code:)
      @current_stage = current_stage
      @expected_current_stage_code = expected_current_stage_code.to_s.strip.downcase.presence
    end

    def call
      return if @expected_current_stage_code.blank?
      return if @current_stage&.code == @expected_current_stage_code

      raise WorkflowTransitionStaleError.new(
        field: 'candidate_workflow_transition.expected_current_stage_code',
        details: {
          expected_current_stage_code: @expected_current_stage_code,
          actual_current_stage_code: @current_stage&.code
        }
      )
    end
  end
end

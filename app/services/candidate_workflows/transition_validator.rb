# frozen_string_literal: true

module CandidateWorkflows
  class TransitionValidator < ApplicationService
    def initialize(actor:, validate_permissions:, expected_current_stage_code:, current_stage:, destination_stage:)
      @actor = actor
      @validate_permissions = validate_permissions
      @expected_current_stage_code = expected_current_stage_code
      @current_stage = current_stage
      @destination_stage = destination_stage
    end

    def call
      validate_actor!
      validate_expected_stage!
      validate_stage_order!
    end

    private

    def validate_actor!
      return unless @validate_permissions
      raise InactiveAccountError unless @actor&.active_staff_account?
      return if @actor.permission?('manage_workflow')

      raise ForbiddenError
    end

    def validate_expected_stage!
      ExpectedStageValidator.call(
        current_stage: @current_stage,
        expected_current_stage_code: @expected_current_stage_code
      )
    end

    def validate_stage_order!
      raise_invalid_transition if @current_stage.blank? || @current_stage.code == 'mobilized'
      return if @destination_stage.position == @current_stage.position + 1

      raise InvalidWorkflowTransitionError.new(
        field: 'candidate_workflow_transition.to_stage_code',
        details: {
          current_stage_code: @current_stage.code,
          to_stage_code: @destination_stage.code
        }
      )
    end

    def raise_invalid_transition
      raise InvalidWorkflowTransitionError.new(field: 'candidate_workflow_transition.to_stage_code')
    end
  end
end

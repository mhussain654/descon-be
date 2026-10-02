# frozen_string_literal: true

module CandidateWorkflows
  class TransitionValidator < ApplicationService
    # rubocop:disable Metrics/ParameterLists
    def initialize(actor:, validate_permissions:, expected_current_stage_code:, current_stage:, destination_stage:,
                   next_process_stage:)
      @actor = actor
      @validate_permissions = validate_permissions
      @expected_current_stage_code = expected_current_stage_code
      @current_stage = current_stage
      @destination_stage = destination_stage
      @next_process_stage = next_process_stage
    end
    # rubocop:enable Metrics/ParameterLists

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

    # The only legal destination is the next stage of the candidate's own
    # process; at the process's terminal stage there is none.
    def validate_stage_order!
      raise_invalid_transition if @current_stage.blank? || @next_process_stage.blank?
      return if @destination_stage.id == @next_process_stage.workflow_stage_id

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

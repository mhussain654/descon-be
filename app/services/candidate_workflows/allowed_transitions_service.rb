# frozen_string_literal: true

module CandidateWorkflows
  class AllowedTransitionsService < ApplicationService
    def initialize(actor:, candidate:)
      @actor = actor
      @candidate = candidate
    end

    def call
      return [] if assignment.blank? || !@candidate.active?

      next_stage = next_stage_for(assignment.current_workflow_stage)
      return [] if next_stage.blank?

      [serialize_stage(next_stage)]
    end

    private

    def assignment
      @assignment ||= @candidate.current_assignment
    end

    def workflow_manageable?
      @actor&.permission?('manage_workflow')
    end

    def next_stage_preview(next_stage)
      TransitionService.transition_prerequisite_result(
        candidate: @candidate,
        assignment:,
        destination_stage: next_stage
      )
    end

    def next_stage_for(current_stage)
      return if current_stage.blank?

      WorkflowStage.find_by(position: current_stage.position + 1)
    end

    def serialize_stage(stage)
      return blocked_for_unauthorized_actor(stage) unless workflow_manageable?

      prerequisite_result = next_stage_preview(stage)
      stage_payload(stage).merge(
        allowed: prerequisite_result.allowed,
        blocking_reasons: prerequisite_result.blocking_reasons
      )
    end

    def stage_payload(stage)
      {
        code: stage.code,
        name: stage.name_for,
        position: stage.position,
        required_fields: TransitionService.required_fields_for(stage.code)
      }
    end

    def blocked_for_unauthorized_actor(stage)
      stage_payload(stage).merge(
        allowed: false,
        blocking_reasons: ['unauthorized_transition']
      )
    end
  end
end

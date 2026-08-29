# frozen_string_literal: true

module CandidateWorkflows
  class AllowedTransitionsService < ApplicationService
    def initialize(actor:, candidate:)
      @actor = actor
      @candidate = candidate
    end

    def call
      return [] unless manageable_workflow?

      next_stage = next_stage_for(assignment.current_workflow_stage)
      return [] if next_stage.blank? || !allowed_next_stage?(next_stage)

      [serialize_stage(next_stage)]
    end

    private

    def assignment
      @assignment ||= @candidate.current_assignment
    end

    def manageable_workflow?
      @actor&.permission?('manage_workflow') && assignment.present? && @candidate.active?
    end

    def allowed_next_stage?(next_stage)
      TransitionService.transition_prerequisites_satisfied?(
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
      {
        code: stage.code,
        name: stage.name_for,
        position: stage.position,
        required_fields: TransitionService.required_fields_for(stage.code)
      }
    end
  end
end

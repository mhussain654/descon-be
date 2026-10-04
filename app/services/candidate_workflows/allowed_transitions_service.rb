# frozen_string_literal: true

module CandidateWorkflows
  class AllowedTransitionsService < ApplicationService
    def initialize(actor:, candidate:)
      @actor = actor
      @candidate = candidate
    end

    def call
      return [] if assignment.blank? || !@candidate.active?

      next_process_stage = assignment.next_process_stage
      return [] if next_process_stage.blank?

      [serialize_stage(next_process_stage)]
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

    def serialize_stage(process_stage)
      return blocked_for_unauthorized_actor(process_stage) unless workflow_manageable?

      prerequisite_result = next_stage_preview(process_stage.workflow_stage)
      stage_payload(process_stage).merge(
        allowed: prerequisite_result.allowed,
        blocking_reasons: prerequisite_result.blocking_reasons
      )
    end

    # `position` is the stage's place in this candidate's process; clients pick
    # the form to show from `action_type`, never from the country.
    def stage_payload(process_stage)
      {
        code: process_stage.code,
        name: process_stage.workflow_stage.name_for,
        position: process_stage.position,
        action_type: process_stage.action_type,
        required: process_stage.required,
        required_fields: TransitionService.required_fields_for(process_stage.code),
        # Every accepted evidence field with its type, whether it's required and
        # (for enums) its values -- enough for a client to build the form.
        fields: StageRequirements.fields_for(process_stage.code)
      }
    end

    def blocked_for_unauthorized_actor(process_stage)
      stage_payload(process_stage).merge(
        allowed: false,
        blocking_reasons: ['unauthorized_transition']
      )
    end
  end
end

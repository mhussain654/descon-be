# frozen_string_literal: true

module CandidateWorkflows
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

    # rubocop:disable Metrics/AbcSize
    def call
      return if assignment.blank? || !@candidate.active?

      while current_stage.position < target_stage.position
        next_stage = WorkflowStage.find_by(position: current_stage.position + 1)
        break if next_stage.blank? || next_stage.position > target_stage.position
        break unless next_stage_allowed?(next_stage)

        transition_to_next_stage!(next_stage)

        assignment.reload
      end

      assignment.current_workflow_stage
    end
    # rubocop:enable Metrics/AbcSize

    private

    def assignment
      @assignment ||= @candidate.current_assignment
    end

    def current_stage
      assignment.current_workflow_stage
    end

    def target_stage
      @target_stage ||= WorkflowStage.find_by!(code: EVENT_TARGETS.fetch(@event))
    end

    def next_stage_allowed?(next_stage)
      TransitionService.transition_prerequisite_result(
        candidate: @candidate,
        assignment:,
        destination_stage: next_stage
      ).allowed
    end

    # rubocop:disable Metrics/MethodLength
    def transition_to_next_stage!(next_stage)
      TransitionService.call(
        actor: @actor,
        candidate: @candidate,
        to_stage_code: next_stage.code,
        request_id: transition_request_id,
        reason_code: reason_code,
        validate_permissions: false
      )
    rescue InvalidWorkflowTransitionError
      assignment.reload
      raise unless assignment.current_workflow_stage.position >= next_stage.position
    end
    # rubocop:enable Metrics/MethodLength

    def transition_request_id
      @request_id.presence || "workflow-auto-#{@event}-#{assignment.public_id}"
    end

    def reason_code
      "auto_#{@event}"
    end
  end
end

# frozen_string_literal: true

module CandidateWorkflows
  # rubocop:disable Metrics/ClassLength
  class TransitionService < ApplicationService
    def self.required_fields_for(stage_code) = StageRequirements.required_fields_for(stage_code)

    def self.transition_prerequisite_result(candidate:, assignment:, destination_stage:)
      new(
        actor: nil,
        candidate:,
        to_stage_code: destination_stage.code,
        request_id: 'workflow-preview',
        validate_permissions: false
      ).send(:prerequisites_satisfied?, assignment:, destination_stage:)
    end

    def initialize(actor:, candidate:, request_id:, validate_permissions: true, **transition_options)
      @actor = actor
      @candidate = candidate
      @request_id = request_id
      @validate_permissions = validate_permissions
      assign_transition_attributes(transition_options)
    end

    def call
      CandidateAssignment.transaction { execute_transition }
    rescue ActiveRecord::RecordNotUnique
      raise InvalidWorkflowTransitionError.new(details: { to_stage_code: @to_stage_code },
                                               field: 'candidate_workflow_transition.to_stage_code')
    end

    private

    def assign_transition_attributes(transition_options)
      @to_stage_code = normalized_code(transition_options[:to_stage_code])
      @expected_current_stage_code = normalized_code(transition_options[:expected_current_stage_code])
      @reason_code = resolved_reason_code(transition_options[:reason_code])
      @note = transition_options[:note].to_s.strip.presence
      @evidence = normalized_evidence(transition_options[:evidence])
    end

    def execute_transition
      context = resolved_transition_context
      validate_transition_request!(**context.slice(:current_stage, :destination_stage))
      validate_prerequisites!(**context.slice(:candidate, :assignment, :destination_stage))

      transitioned_at = Time.current
      persist_workflow_state!(context:, transitioned_at:)
      history_entry = record_transition!(context:, transitioned_at:)
      record_post_transition_events!(history_entry:, context:, transitioned_at:)
      { history_entry:, snapshot: StateSnapshotService.call(candidate: context.fetch(:candidate)) }
    end

    def validate_prerequisites!(candidate:, assignment:, destination_stage:)
      result = prerequisite_validator(candidate:, assignment:, destination_stage:).call
      return if result.allowed

      raise WorkflowTransitionPrerequisiteError.new(
        field: result.field,
        details: {
          to_stage_code: destination_stage.code,
          required_fields: result.required_fields,
          blocking_reasons: result.blocking_reasons
        }
      )
    end

    def prerequisite_validator(candidate:, assignment:, destination_stage:)
      PrerequisiteValidator.new(candidate:, assignment:, destination_stage:, evidence: @evidence)
    end

    def prerequisites_satisfied?(assignment:, destination_stage:, candidate: @candidate)
      prerequisite_validator(candidate:, assignment:, destination_stage:).call
    end

    def validate_transition_request!(current_stage:, destination_stage:)
      TransitionValidator.call(
        actor: @actor,
        validate_permissions: @validate_permissions,
        expected_current_stage_code: @expected_current_stage_code,
        current_stage:,
        destination_stage:
      )
    end

    def record_transition!(context:, transitioned_at:)
      TransitionRecorder.call(
        actor: @actor,
        context:,
        transition: transition_record(transitioned_at)
      )
    end

    def record_post_transition_events!(history_entry:, context:, transitioned_at:)
      TransitionSideEffectRecorder.call(
        history_entry:,
        context:,
        transition: transition_record(transitioned_at)
      )
    end

    def normalized_code(value) = value.to_s.strip.downcase.presence

    def resolved_reason_code(value)
      return 'qatar_bu_shared' if @to_stage_code == 'documents_shared_with_qatar_bu'

      normalized_code(value)
    end

    def normalized_evidence(evidence)
      evidence.to_h.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_s] = value.is_a?(String) ? value.strip.presence : value
      end.compact
    end

    def resolved_transition_context
      TransitionContextResolver.call(candidate: @candidate, to_stage_code: @to_stage_code)
    end

    def persist_workflow_state!(context:, transitioned_at:)
      context.fetch(:candidate).update!(status_code: context.fetch(:destination_stage).code)
      context.fetch(:assignment).update!(
        current_workflow_stage: context.fetch(:destination_stage),
        updated_at: transitioned_at
      )
    end

    def transition_record(transitioned_at)
      {
        transitioned_at:,
        request_id: @request_id,
        reason_code: @reason_code,
        note: @note,
        evidence: @evidence
      }
    end
  end
  # rubocop:enable Metrics/ClassLength
end

# frozen_string_literal: true

module CandidateWorkflows
  class TransitionRecorder < ApplicationService
    def initialize(actor:, transition:, context:)
      @actor = actor
      @transition = transition
      @context = context
    end

    def call
      history_entry = CandidateStageHistory.create!(history_attributes)
      AuditEvent.create!(audit_attributes)
      history_entry
    end

    private

    def history_attributes
      {
        candidate_assignment: @context.fetch(:assignment),
        from_workflow_stage: @context.fetch(:current_stage),
        to_workflow_stage: @context.fetch(:destination_stage),
        actor: @actor,
        occurred_at: @transition.fetch(:transitioned_at),
        reason_code: @transition.fetch(:reason_code),
        note: @transition.fetch(:note),
        metadata: @transition.fetch(:evidence)
      }
    end

    def audit_attributes
      base_audit_attributes.merge(metadata: audit_metadata, occurred_at: @transition.fetch(:transitioned_at))
    end

    def audit_metadata
      {
        actor_public_id: @actor&.public_id,
        candidate_public_id: @context.fetch(:candidate).public_id,
        candidate_assignment_public_id: @context.fetch(:assignment).public_id,
        from_stage_code: @context.fetch(:current_stage).code,
        to_stage_code: @context.fetch(:destination_stage).code,
        details: @transition.fetch(:evidence)
      }.compact
    end

    def base_audit_attributes
      {
        actor: @actor,
        candidate: @context.fetch(:candidate),
        candidate_assignment: @context.fetch(:assignment),
        entity_type: 'CandidateAssignment',
        entity_id: @context.fetch(:assignment).id,
        action_code: 'candidate_workflow_transitioned',
        reason_code: @transition.fetch(:reason_code),
        request_id: @transition.fetch(:request_id)
      }
    end
  end
end

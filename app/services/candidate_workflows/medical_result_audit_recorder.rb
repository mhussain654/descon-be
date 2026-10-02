# frozen_string_literal: true

module CandidateWorkflows
  # Audits one recorded medical result -- from the transition into the
  # medical-outcome stage, or a later re-decision while the candidate is held.
  class MedicalResultAuditRecorder < ApplicationService
    def initialize(actor:, request_id:, context:)
      @actor = actor
      @request_id = request_id
      @context = context
    end

    def call
      AuditEvent.create!(
        actor: @actor, candidate:, candidate_assignment: assignment,
        entity_type: 'CandidateMedicalResult', entity_id: result.id,
        action_code: 'candidate_medical_result_recorded', request_id: @request_id,
        metadata: audit_metadata, occurred_at: Time.current
      )
    end

    private

    def result = @context.fetch(:result)

    def candidate = @context.fetch(:candidate)

    def assignment = @context.fetch(:assignment)

    def audit_metadata
      {
        candidate_public_id: candidate.public_id,
        candidate_assignment_public_id: assignment.public_id,
        medical_result_public_id: result.public_id,
        outcome_code: result.outcome_code,
        result_date: result.result_date.iso8601,
        re_decision: result.candidate_stage_history_id.nil?
      }
    end
  end
end

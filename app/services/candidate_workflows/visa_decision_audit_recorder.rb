# frozen_string_literal: true

module CandidateWorkflows
  class VisaDecisionAuditRecorder < ApplicationService
    def initialize(actor:, request_id:, context:)
      @actor = actor
      @request_id = request_id
      @context = context
    end

    def call = AuditEvent.create!(audit_event_attributes)

    private

    def decision = @context.fetch(:decision)

    def candidate = @context.fetch(:candidate)

    def assignment = @context.fetch(:assignment)

    def audit_metadata
      {
        candidate_public_id: candidate.public_id,
        candidate_assignment_public_id: assignment.public_id,
        visa_decision_public_id: decision.public_id,
        outcome_code: decision.outcome_code,
        decision_date: decision.decision_date.iso8601,
        rejection_reason_code: decision.rejection_reason_code
      }.compact
    end

    def audit_event_attributes
      {
        actor: @actor,
        candidate: candidate,
        candidate_assignment: assignment,
        metadata: audit_metadata
      }.merge(entity_attributes)
    end

    def entity_attributes
      {
        entity_type: 'CandidateVisaDecision',
        entity_id: decision.id,
        action_code: 'candidate_visa_decision_recorded',
        request_id: @request_id,
        occurred_at: Time.current
      }
    end
  end
end

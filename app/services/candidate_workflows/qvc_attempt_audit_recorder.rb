# frozen_string_literal: true

module CandidateWorkflows
  class QvcAttemptAuditRecorder < ApplicationService
    ACTION_CODE_BY_EVENT = {
      scheduled: 'candidate_qvc_attempt_scheduled',
      completed: 'candidate_qvc_attempt_completed'
    }.freeze

    def initialize(event:, actor:, request_id:, context:)
      @event = event
      @actor = actor
      @request_id = request_id
      @context = context
    end

    def call
      AuditEvent.create!(audit_event_attributes)
    end

    private

    def occurred_at
      attempt.outcome_recorded_at || attempt.created_at
    end

    def audit_metadata
      {
        candidate_public_id: candidate.public_id,
        candidate_assignment_public_id: assignment.public_id,
        qvc_attempt_public_id: attempt.public_id,
        attempt_number: attempt.attempt_number,
        appointment_date: attempt.appointment_date.iso8601,
        outcome_code: attempt.outcome_code,
        no_show: attempt.no_show
      }.compact
    end

    def audit_event_attributes
      {
        actor: @actor,
        candidate: candidate,
        candidate_assignment: assignment,
        **entity_attributes,
        **event_attributes,
        metadata: audit_metadata
      }
    end

    def entity_attributes
      {
        entity_type: 'CandidateQvcAttempt',
        entity_id: attempt.id
      }
    end

    def event_attributes
      {
        action_code: ACTION_CODE_BY_EVENT.fetch(@event),
        request_id: @request_id,
        occurred_at:
      }
    end

    def candidate = @context.fetch(:candidate)

    def assignment = @context.fetch(:assignment)

    def attempt = @context.fetch(:attempt)
  end
end

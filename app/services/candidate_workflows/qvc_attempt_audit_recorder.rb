# frozen_string_literal: true

module CandidateWorkflows
  class QvcAttemptAuditRecorder < ApplicationService
    ACTION_CODE_BY_EVENT = {
      scheduled: 'candidate_qvc_attempt_scheduled',
      completed: 'candidate_qvc_attempt_completed'
    }.freeze

    def initialize(event:, candidate:, assignment:, attempt:, actor:, request_id:)
      @event = event
      @candidate = candidate
      @assignment = assignment
      @attempt = attempt
      @actor = actor
      @request_id = request_id
    end

    def call
      AuditEvent.create!(
        actor: @actor,
        candidate: @candidate,
        candidate_assignment: @assignment,
        entity_type: 'CandidateQvcAttempt',
        entity_id: @attempt.id,
        action_code: ACTION_CODE_BY_EVENT.fetch(@event),
        request_id: @request_id,
        occurred_at: occurred_at,
        metadata: audit_metadata
      )
    end

    private

    def occurred_at
      @attempt.outcome_recorded_at || @attempt.created_at
    end

    def audit_metadata
      {
        candidate_public_id: @candidate.public_id,
        candidate_assignment_public_id: @assignment.public_id,
        qvc_attempt_public_id: @attempt.public_id,
        attempt_number: @attempt.attempt_number,
        appointment_date: @attempt.appointment_date.iso8601,
        outcome_code: @attempt.outcome_code,
        no_show: @attempt.no_show
      }.compact
    end
  end
end

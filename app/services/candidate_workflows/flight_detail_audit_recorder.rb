# frozen_string_literal: true

module CandidateWorkflows
  class FlightDetailAuditRecorder < ApplicationService
    ACTION_CODE_BY_EVENT = {
      recorded: 'candidate_flight_detail_recorded',
      mobilized: 'candidate_mobilized'
    }.freeze

    def initialize(event:, actor:, request_id:, context:)
      @event = event
      @actor = actor
      @request_id = request_id
      @context = context
    end

    def call = AuditEvent.create!(audit_event_attributes)

    private

    def detail = @context.fetch(:detail)

    def candidate = @context.fetch(:candidate)

    def assignment = @context.fetch(:assignment)

    def audit_metadata
      flight_metadata.merge(mobilization_metadata).compact
    end

    def flight_metadata
      {
        candidate_public_id: candidate.public_id,
        candidate_assignment_public_id: assignment.public_id,
        flight_detail_public_id: detail.public_id,
        airline: detail.airline,
        flight_number: detail.flight_number,
        sector: detail.sector,
        flight_departure_at: detail.flight_departure_at.utc.iso8601
      }
    end

    def mobilization_metadata
      { mobilized_on: detail.mobilized_on&.iso8601 }
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
        entity_type: 'CandidateFlightDetail',
        entity_id: detail.id,
        action_code: ACTION_CODE_BY_EVENT.fetch(@event),
        request_id: @request_id,
        occurred_at: Time.current
      }
    end
  end
end

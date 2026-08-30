# frozen_string_literal: true

module CandidateWorkflows
  class PostTransitionEventRecorder < ApplicationService
    EVENT_CODE = 'documents_shared_with_qatar_bu_confirmed'

    def initialize(history_entry:, context:, transition:)
      @history_entry = history_entry
      @context = context
      @transition = transition
    end

    def call
      return unless qatar_sharing_transition?

      CandidateWorkflowEvent.create!(event_attributes)
    end

    private

    def qatar_sharing_transition?
      @context.fetch(:destination_stage).code == 'documents_shared_with_qatar_bu'
    end

    def event_attributes
      {
        candidate: @context.fetch(:candidate),
        candidate_assignment: @context.fetch(:assignment),
        candidate_stage_history: @history_entry,
        actor: @history_entry.actor,
        event_code: EVENT_CODE,
        request_id: @transition.fetch(:request_id),
        occurred_at: @history_entry.occurred_at,
        payload: event_payload
      }
    end

    def event_payload
      {
        candidate_public_id: @context.fetch(:candidate).public_id,
        candidate_assignment_public_id: @context.fetch(:assignment).public_id,
        actor_public_id: @history_entry.actor&.public_id,
        to_stage_code: @context.fetch(:destination_stage).code,
        occurred_at: @history_entry.occurred_at.utc.iso8601
      }.compact
    end
  end
end

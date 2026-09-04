# frozen_string_literal: true

module Admin
  # Read-only view of an AuditEvent for the staff audit explorer (MPS-807).
  # `metadata` is passed through as-is -- every existing *AuditRecorder
  # service already writes only public ids, codes and non-sensitive field
  # names into it (confirmed across every AuditEvent.create! call site: no
  # raw CNIC, passport, bank or payment identifier is ever stored there),
  # so this serializer has nothing further to mask.
  class AuditEventSerializer
    def initialize(event)
      @event = event
    end

    def as_json(*)
      entity_attributes.merge(context_attributes)
    end

    private

    def entity_attributes
      {
        id: @event.id,
        actor: actor_reference,
        action_code: @event.action_code,
        entity_type: @event.entity_type,
        entity_id: @event.entity_id
      }
    end

    def context_attributes
      {
        candidate_id: @event.candidate&.public_id,
        reason_code: @event.reason_code,
        note: @event.note,
        request_id: @event.request_id,
        occurred_at: @event.occurred_at.utc.iso8601,
        metadata: @event.metadata
      }
    end

    def actor_reference
      return nil if @event.actor.blank?

      { id: @event.actor.public_id, role: @event.actor.role }
    end
  end
end

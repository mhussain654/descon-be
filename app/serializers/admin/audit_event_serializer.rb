# frozen_string_literal: true

module Admin
  # Read-only view of an AuditEvent for the staff audit explorer (MPS-807).
  # `metadata` is filtered through AuditEventMetadataSanitizer's allowlist --
  # trusting every existing/future *AuditRecorder to only ever write safe
  # field names is not a durable security boundary on its own, so this is
  # the enforcement point, not just the frontend's own defense-in-depth
  # masking. `note` (free-form staff-entered text) is deliberately not
  # returned here at all: nothing in the audit explorer's list view
  # currently displays it, and it carries the same "arbitrary free text"
  # risk as the blocked metadata keys above.
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
        request_id: @event.request_id,
        occurred_at: @event.occurred_at.utc.iso8601,
        metadata: AuditEventMetadataSanitizer.sanitize(@event.metadata)
      }
    end

    def actor_reference
      return nil if @event.actor.blank?

      { id: @event.actor.public_id, role: @event.actor.role }
    end
  end
end

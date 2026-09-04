# frozen_string_literal: true

module Admin
  module Payments
    # A safe, staff-facing view of one payment event. Deliberately never
    # exposes `payload` (the raw provider callback/return body -- may carry
    # provider secrets or signatures), `provider_order_id`/
    # `provider_transaction_id`/`request_id` (internal correlation only, not
    # something staff act on), or the payment's foreign key (the parent
    # payment is already the context this is nested under).
    class PaymentEventSerializer
      def initialize(event)
        @event = event
      end

      def as_json(*)
        {
          id: @event.event_key,
          event_type: @event.event_type,
          event_source: @event.event_source,
          provider_status_code: @event.provider_status_code,
          occurred_at: @event.occurred_at.utc.iso8601,
          actor: serialized_actor
        }.compact
      end

      private

      def serialized_actor
        actor = @event.actor
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end
    end
  end
end

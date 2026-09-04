# frozen_string_literal: true

module Admin
  module Payments
    # The full payment-detail payload: everything PaymentSummarySerializer
    # exposes plus the safe payment-event history and this payment's own
    # reconciliation findings -- the sole source of truth for a payment's
    # current state, never derived or cached anywhere else on the frontend.
    class PaymentDetailSerializer
      def initialize(payment)
        @payment = payment
        @summary = PaymentSummarySerializer.new(payment)
      end

      def as_json(*)
        @summary.as_json.merge(
          payment_events: serialized_events,
          reconciliation_findings: serialized_findings
        )
      end

      private

      # Sorted with Ruby's own #sort_by, not AR's #order -- calling #order on
      # an already-preloaded association issues a brand new query instead of
      # using the preloaded rows, silently reintroducing the N+1 the
      # controller's preload was there to prevent.
      def serialized_events
        @payment.payment_events.to_a.sort_by(&:occurred_at).map { |event| PaymentEventSerializer.new(event).as_json }
      end

      def serialized_findings
        @payment.payment_reconciliation_findings.to_a.sort_by(&:created_at).map do |finding|
          ReconciliationFindingSerializer.new(finding).as_json
        end
      end
    end
  end
end

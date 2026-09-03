# frozen_string_literal: true

module Admin
  module Payments
    # One transaction-list row, or the base of PaymentDetailSerializer.
    # `reconciliation_state` is derived from the payment's own (preloaded --
    # never queried per-row) reconciliation findings: 'open' if any finding is
    # still open, 'resolved' if every finding has been resolved, 'clean' if
    # reconciliation has never flagged this payment at all.
    class PaymentSummarySerializer
      def initialize(payment)
        @payment = payment
      end

      def as_json(*)
        attributes.compact
      end

      private

      def attributes
        identity_attributes.merge(timestamp_attributes)
      end

      def identity_attributes
        {
          id: @payment.public_id, candidate: serialized_candidate,
          payment_type_code: @payment.payment_type_code, status: @payment.status_code,
          amount: @payment.amount.to_s('F'), currency_code: @payment.currency_code, provider: @payment.provider_code,
          external_reference: @payment.external_reference, reconciliation_state: reconciliation_state
        }
      end

      def timestamp_attributes
        {
          paid_at: @payment.paid_at&.utc&.iso8601,
          created_at: @payment.created_at.utc.iso8601, updated_at: @payment.updated_at.utc.iso8601
        }
      end

      def serialized_candidate
        candidate = @payment.candidate_assignment.candidate

        {
          id: candidate.public_id,
          full_name: candidate.full_name,
          masked_cnic: ::Candidates::CnicMasker.call(candidate.cnic),
          reference_number: @payment.candidate_assignment.reference_number
        }
      end

      def reconciliation_state
        findings = @payment.payment_reconciliation_findings.to_a
        return 'clean' if findings.empty?
        return 'open' if findings.any?(&:open?)

        'resolved'
      end
    end
  end
end

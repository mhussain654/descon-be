# frozen_string_literal: true

module Payments
  # The ways of paying the fee that the candidate has started and not finished: a
  # payment code (voucher) that is unpaid and not expired, and a card checkout that
  # has not expired. The candidate may have both and pays whichever they choose; the
  # screen warns them to pay only one. If both are ever paid, reconciliation flags
  # the duplicate for finance (see Payments::ReconciliationService).
  class OpenPayments
    def self.voucher(assignment)
      open_payments(assignment).find(&:voucher?)
    end

    def self.card_checkout_open?(assignment)
      open_payments(assignment).any? { |payment| !payment.voucher? }
    end

    def self.open_payments(assignment)
      return [] if assignment.blank?

      assignment.payments.latest_first.select do |payment|
        payment.checkout_pending? && payment.checkout_expires_at&.future?
      end
    end
    private_class_method :open_payments
  end
end

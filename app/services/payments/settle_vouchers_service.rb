# frozen_string_literal: true

module Payments
  # Asks KuickPay which vouchers were paid (Bill Payment Bulk Inquiry, for today and
  # yesterday in Pakistan time, since a payment can be noticed after midnight) and marks
  # the matching unpaid voucher payments paid -- through the same state applier,
  # validation and event trail as a card payment. A voucher counts as paid as soon as it
  # is listed -- KuickPay lists it before it settles the money to Descon. KuickPay never calls us, so this
  # is how a voucher payment is noticed. Safe to run repeatedly: a settlement already
  # recorded is skipped. A settlement that does not match (wrong amount, unknown
  # voucher) is logged and left for finance to see; it never stops the others.
  class SettleVouchersService < ApplicationService
    TIME_ZONE = 'Asia/Karachi'
    DAYS_BACK = 1

    def initialize(request_id: SecureRandom.uuid)
      @request_id = request_id
      @configuration = Payments::Configuration.new
    end

    def call
      return 0 unless adapter.available?
      return 0 unless Payment.exists?(provider_code: adapter.provider_code, status_code: 'checkout_pending')

      settlements.count { |settlement| settle(settlement) }
    end

    private

    def settlements
      today = Time.current.in_time_zone(TIME_ZONE).to_date
      (0..DAYS_BACK).flat_map { |back| adapter.settlements_on(date: today - back) }
    end

    # True only when this call marked a payment paid.
    def settle(settlement)
      CandidateAssignment.transaction { mark_paid(settlement) }.present?
    rescue PaymentNotificationMismatchError, PaymentNotificationConflictError => e
      Rails.logger.warn("KuickPay voucher settlement not applied (#{e.class}): consumer=#{settlement.consumer_number}")
      false
    end

    # The payment that was marked paid, or nil if there was nothing to do.
    def mark_paid(settlement)
      payment = Payment.lock.find_by(provider_code: adapter.provider_code, voucher_number: settlement.consumer_number)
      return if payment.blank? || payment.paid?

      notification = notification_for(payment, settlement)
      return if PaymentEvent.exists?(provider_code: notification.provider_code, event_key: notification.event_key)

      apply(payment, notification)
      payment
    end

    def apply(payment, notification)
      assignment = CandidateAssignment.lock.find(payment.candidate_assignment_id)
      candidate = Candidate.lock.find(assignment.candidate_id)
      Payments::NotificationValidator.call(payment:, notification:)
      Payments::PaymentStateApplier.call(payment:, assignment:, candidate:, notification:, request_id: @request_id)
      Payments::NotificationEventRecorder.call(payment:, assignment:, notification:, request_id: @request_id)
    end

    def notification_for(payment, settlement)
      Payments::Providers::Notification.new(
        provider_code: adapter.provider_code, event_source: 'settlement_inquiry',
        event_key: "settled:#{settlement.consumer_number}:#{settlement.auth_id}",
        provider_order_id: payment.provider_order_id, provider_transaction_id: settlement.auth_id,
        provider_status_code: 'SUCCESS', provider_response_code: '00', amount: settlement.amount,
        currency_code: payment.currency_code, occurred_at: settlement.paid_at || Time.current,
        payload: { consumer_number: settlement.consumer_number, auth_id: settlement.auth_id, bank: settlement.bank,
                   amount: settlement.amount.to_s('F') }
      )
    end

    def adapter
      @adapter ||= Payments::ProviderRegistry.fetch('kuickpay_voucher')
    end
  end
end

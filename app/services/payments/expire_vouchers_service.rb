# frozen_string_literal: true

module Payments
  # Closes vouchers that were never paid. A voucher is given two days of grace after
  # its expiry and is then marked cancelled. A payment made on its last day is only
  # checked for at 10:00 the next day (Payments::PollVoucherSettlementsJob), so one day
  # of grace could close it first. The candidate never sees the grace: the app already
  # treats a voucher past its expiry as expired and lets them get a new code.
  class ExpireVouchersService < ApplicationService
    GRACE = 2.days

    def call
      Payment.where(provider_code: 'kuickpay_voucher', status_code: 'checkout_pending')
             .where(checkout_expires_at: ...(Time.current - GRACE)).find_each { |payment| expire(payment) }
    end

    private

    def expire(payment)
      payment.with_lock do
        next unless payment.checkout_pending?

        payment.update!(status_code: 'cancelled', provider_status_code: 'EXPIRED')
        Payments::AuditRecorder.call(
          action: :cancelled, payment:, candidate: payment.candidate_assignment.candidate,
          assignment: payment.candidate_assignment, request_id: SecureRandom.uuid,
          metadata: { provider_status_code: 'EXPIRED' }
        )
      end
    end
  end
end

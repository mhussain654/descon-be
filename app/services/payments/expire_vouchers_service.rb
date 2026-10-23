# frozen_string_literal: true

module Payments
  # Closes vouchers that were never paid. A voucher is given a day of grace after its
  # expiry (a payment can settle late) and is then marked cancelled, which also lets
  # the candidate get a new code or pay by card. The candidate never sees the grace
  # day: the app already treats a voucher past its expiry as expired.
  class ExpireVouchersService < ApplicationService
    GRACE = 1.day

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

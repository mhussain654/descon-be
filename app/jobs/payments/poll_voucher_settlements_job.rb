# frozen_string_literal: true

module Payments
  # Notices paid vouchers, then closes expired ones. KuickPay allows only five Bill
  # Payment Bulk Inquiry calls a day, so this runs at five fixed Pakistan times
  # (config/recurring.yml) with one call each: 13:00, 16:00, 19:00 and 23:00 check
  # today, and 10:00 checks yesterday, catching what was paid after the 23:00 check.
  # A provider outage only skips that run; the next one for the same day catches up.
  class PollVoucherSettlementsJob < ApplicationJob
    DAYS_AGO = { 'today' => 0, 'yesterday' => 1 }.freeze

    queue_as :default

    def perform(day = 'today')
      Payments::SettleVouchersService.call(days_ago: DAYS_AGO.fetch(day))
      Payments::ExpireVouchersService.call
    rescue PaymentCheckoutUnavailableError
      Rails.logger.warn("KuickPay voucher settlement poll skipped (#{day}): provider unavailable")
    end
  end
end

# frozen_string_literal: true

module Payments
  # Runs every few minutes (config/recurring.yml): notices paid vouchers, then closes
  # expired ones. A provider outage only skips this run; the next one catches up.
  class PollVoucherSettlementsJob < ApplicationJob
    queue_as :default

    def perform
      Payments::SettleVouchersService.call
      Payments::ExpireVouchersService.call
    rescue PaymentCheckoutUnavailableError
      Rails.logger.warn('KuickPay voucher settlement poll skipped: provider unavailable')
    end
  end
end

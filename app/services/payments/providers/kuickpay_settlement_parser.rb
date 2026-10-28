# frozen_string_literal: true

module Payments
  module Providers
    # Reads one row of KuickPay's Bill Payment Bulk Inquiry into a paid voucher. KuickPay
    # lists a payment as soon as the candidate has made it -- before it settles the money to
    # Descon (`isSettled`, about a working day later) -- so settling is not required for a
    # row to count. A row with no voucher number or an unreadable amount is skipped.
    class KuickpaySettlementParser < ApplicationService
      Settlement = Struct.new(:consumer_number, :registration_number, :amount, :auth_id, :bank, :paid_at,
                              keyword_init: true)
      # KuickPay sends its times in UTC, not Pakistan time: a UAT voucher created at 06:29 UTC came back paid
      # with tranTime 063119 (checked 2026-10-28).
      KUICKPAY_ZONE = ActiveSupport::TimeZone['UTC']

      def initialize(row)
        @row = row
      end

      def call
        return if @row['consumer_Number'].blank?

        Settlement.new(**identity, amount: BigDecimal(@row['amountTransaction'].to_s), paid_at:)
      rescue ArgumentError
        nil
      end

      private

      def identity
        {
          consumer_number: @row['consumer_Number'].to_s, registration_number: @row['registrationNumber'].to_s.presence,
          auth_id: @row['authID'].to_s.presence, bank: @row['bank'].to_s.presence
        }
      end

      # When the candidate paid (KuickPay's UTC clock): the settlement time once there is one, otherwise the
      # transaction date (KuickPay sends it at midnight) plus the time of day it sends separately (`tranTime`,
      # HHMMSS). nil when neither can be read; the caller then uses the time it noticed the payment.
      def paid_at
        return KUICKPAY_ZONE.parse(@row['settlement_Date_Time']) if @row['settlement_Date_Time'].present?

        KUICKPAY_ZONE.parse("#{@row['transaction_Date_Time'].to_s[0, 10]} #{time_of_day}")
      rescue ArgumentError
        nil
      end

      def time_of_day
        clock = @row['tranTime'].to_s
        clock.match?(/\A\d{6}\z/) ? "#{clock[0, 2]}:#{clock[2, 2]}:#{clock[4, 2]}" : '00:00:00'
      end
    end
  end
end

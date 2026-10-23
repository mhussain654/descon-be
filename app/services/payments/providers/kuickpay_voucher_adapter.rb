# frozen_string_literal: true

module Payments
  module Providers
    # KuickPay's "Hybrid" voucher model: we create a voucher (consumer) number for
    # the candidate's fee, the candidate pays that number from a wallet or bank app,
    # and we later ask KuickPay which vouchers were settled. KuickPay never calls
    # into our system. Kept apart from the hosted card checkout adapter -- a
    # different API, host and credentials.
    class KuickpayVoucherAdapter
      INSERT_VOUCHER_PATH = '/api/insertPPMVoucher'
      BULK_INQUIRY_PATH = '/api/BillPaymentBulkInquiry'
      SUCCESS_CODE = '00'
      FEE_HEAD = 'Fee'

      # `consumer_number` is the payable voucher number; `system_voucher_number` is KuickPay's own.
      Voucher = Struct.new(:consumer_number, :system_voucher_number, :raw_response, keyword_init: true)

      # One settled transaction from the bulk inquiry.
      Settlement = Struct.new(:consumer_number, :registration_number, :amount, :auth_id, :bank, :settled_at,
                              keyword_init: true)

      def initialize(configuration:)
        @configuration = configuration
        @http_client = KuickpayHybridHttpClient.new(configuration:)
      end

      def provider_code = 'kuickpay_voucher'

      def available?
        @configuration.kuickpay_voucher_enabled? &&
          @configuration.kuickpay_hybrid_username.present? &&
          @configuration.kuickpay_hybrid_password.present? &&
          @configuration.kuickpay_institution_id.present?
      end

      def create_voucher(payment:, candidate:, expires_on:)
        raise PaymentCheckoutUnavailableError unless available?

        body = perform(INSERT_VOUCHER_PATH, voucher_payload(payment:, candidate:, expires_on:), 'insert_voucher')
        Voucher.new(consumer_number: body.fetch('response_description').to_s, raw_response: body,
                    system_voucher_number: body['response_detail'].to_s.presence)
      rescue KeyError
        reject!('insert voucher response had no voucher number')
      end

      # Every settled transaction KuickPay reports for one day (Pakistan time).
      def settlements_on(date:)
        raise PaymentCheckoutUnavailableError unless available?

        body = perform(BULK_INQUIRY_PATH, { institutionID: @configuration.kuickpay_institution_id,
                                            transactionDate: date.strftime('%Y%m%d') }, 'bulk_inquiry')
        Array(body['transactionList']).filter_map { |row| build_settlement(row) }
      end

      private

      def perform(path, payload, step)
        response = @http_client.post(path:, payload:, step:)
        body = JSON.parse(response.body)
        return body if response.is_a?(Net::HTTPSuccess) && body['response_Code'] == SUCCESS_CODE

        reject!("#{step} refused: #{body.is_a?(Hash) ? body['response_Code'] : response.code}")
      rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error => e
        reject!("#{step} failed: #{e.class}")
      end

      def reject!(detail)
        Rails.logger.warn("KuickPay voucher request failed: #{detail}")
        raise PaymentCheckoutUnavailableError
      end

      def build_settlement(row)
        return unless row['isSettled'] == true && row['consumer_Number'].present?

        Settlement.new(settlement_identity(row).merge(amount: BigDecimal(row['amountTransaction'].to_s),
                                                      settled_at: parse_time(row['settlement_Date_Time'])))
      rescue ArgumentError
        nil
      end

      def settlement_identity(row)
        {
          consumer_number: row['consumer_Number'].to_s, registration_number: row['registrationNumber'].to_s.presence,
          auth_id: row['authID'].to_s.presence, bank: row['bank'].to_s.presence
        }
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) || Time.current
      end

      # KuickPay's voucher takes whole rupees; the due date and expiry are the same day
      # (no late fee), and a voucher needs an email, which candidates do not have.
      def voucher_payload(payment:, candidate:, expires_on:)
        amount = whole_rupees(payment.amount)
        today = Time.current.in_time_zone('Asia/Karachi').to_date
        identity_payload(payment:, candidate:).merge(
          head1: FEE_HEAD, amount1: amount, totalAmount: amount, amountAfterDueDate: amount,
          dueDate: expires_on.iso8601, expiryDate: expires_on.iso8601, issueDate: today.iso8601,
          voucherMonth: today.strftime('%m'), voucherYear: today.strftime('%Y')
        )
      end

      def identity_payload(payment:, candidate:)
        {
          institutionID: @configuration.kuickpay_institution_id, registrationNumber: payment.provider_order_id,
          name: alphabetic_name(candidate.full_name), mobile: local_mobile(candidate.mobile_number),
          email: @configuration.voucher_fallback_email
        }
      end

      def whole_rupees(amount)
        return amount.to_i if amount == amount.to_i

        reject!('fee is not a whole number of rupees')
      end

      def alphabetic_name(name)
        name.to_s.gsub(/[^[:alpha:] ]/, '').squish.presence || 'Candidate'
      end

      # KuickPay wants the local form (03001234567), our stored number is +923001234567.
      def local_mobile(number)
        normalized = PhoneNumbers::Normalizer.call(number).to_s
        normalized.start_with?('+92') ? "0#{normalized.delete_prefix('+92')}" : normalized.delete_prefix('+')
      end
    end
  end
end

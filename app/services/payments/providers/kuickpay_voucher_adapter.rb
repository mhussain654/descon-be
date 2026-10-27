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

      def initialize(configuration:)
        @configuration = configuration
        @http_client = KuickpayHybridHttpClient.new(configuration:)
      end

      def provider_code = 'kuickpay_voucher'

      # Needs both logins: a voucher is only issued when we can also find out that it was paid.
      def available?
        @configuration.kuickpay_voucher_enabled? && logins_present? &&
          [@configuration.kuickpay_institution_id, @configuration.kuickpay_hybrid_base_url].all?(&:present?)
      end

      def create_voucher(payment:, candidate:, expires_on:)
        raise PaymentCheckoutUnavailableError unless available?

        body = perform(INSERT_VOUCHER_PATH, voucher_payload(payment:, candidate:, expires_on:), 'insert_voucher',
                       username: @configuration.kuickpay_hybrid_username,
                       password: @configuration.kuickpay_hybrid_password)
        Voucher.new(consumer_number: body.fetch('response_description').to_s, raw_response: body,
                    system_voucher_number: system_voucher_number(body))
      rescue KeyError
        reject!('insert voucher response had no voucher number')
      end

      # Every payment KuickPay reports for one day (Pakistan time), settled or not yet.
      def settlements_on(date:)
        raise PaymentCheckoutUnavailableError unless available?

        body = perform(BULK_INQUIRY_PATH, { institutionID: @configuration.kuickpay_institution_id,
                                            transactionDate: date.strftime('%Y%m%d') }, 'bulk_inquiry',
                       username: @configuration.kuickpay_payment_status_username,
                       password: @configuration.kuickpay_payment_status_password)
        Array(body['transactionList']).filter_map { |row| KuickpaySettlementParser.call(row) }
      end

      private

      def logins_present?
        [@configuration.kuickpay_hybrid_username, @configuration.kuickpay_hybrid_password,
         @configuration.kuickpay_payment_status_username,
         @configuration.kuickpay_payment_status_password].all?(&:present?)
      end

      def perform(path, payload, step, username:, password:)
        response = @http_client.post(path:, payload:, step:, username:, password:)
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

      # KuickPay answers `responseCode_Detail`; `response_detail` is what its PDF calls it.
      def system_voucher_number(body)
        (body['responseCode_Detail'].presence || body['response_detail']).to_s.presence
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
          institutionID: @configuration.kuickpay_institution_id,
          registrationNumber: payment.provider_order_id.delete('-'),
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

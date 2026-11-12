# frozen_string_literal: true

module Payments
  module Providers
    # KuickPay's Send SMS: KuickPay texts the candidate their voucher (consumer) number, the fee and the due date.
    # KuickPay does not text it when the voucher is created, so we ask. It lives on KuickPay's live API host and
    # uses the voucher (Hybrid) login. Only KuickpayVoucherAdapter#send_voucher_sms uses it, after checking that
    # vouchers are set up. Returns KuickPay's reply, which is kept as the payment's event.
    class KuickpayVoucherSms
      PATH = '/api/sendSMS'
      SUCCESS_CODE = '00'
      TIME_ZONE = 'Asia/Karachi'

      def initialize(configuration:)
        @configuration = configuration
        @http_client = KuickpayHybridHttpClient.new(configuration:, base_url: configuration.kuickpay_sms_base_url)
      end

      def deliver(payment:, candidate:)
        response = @http_client.post(
          path: PATH, payload: payload(payment:, candidate:), step: 'send_sms',
          username: @configuration.kuickpay_hybrid_username, password: @configuration.kuickpay_hybrid_password
        )
        reply!(response)
      rescue SocketError, SystemCallError, Timeout::Error => e
        reject!("failed: #{e.class}")
      end

      private

      # KuickPay wants the due date as 15-Apr-2026, the fee in whole rupees (a voucher is only ever issued for
      # whole rupees) and the local mobile number.
      def payload(payment:, candidate:)
        {
          InstitutionID: @configuration.kuickpay_institution_id,
          duedate: payment.checkout_expires_at.in_time_zone(TIME_ZONE).to_date.strftime('%d-%b-%Y'),
          amount: payment.amount.to_i.to_s, consumerNo: payment.voucher_number,
          cellNumberSMS: KuickpayVoucherAdapter.local_mobile(candidate.mobile_number)
        }
      end

      # The reply's shape is not documented, so any successful HTTP reply counts unless it carries a KuickPay
      # response code other than success.
      def reply!(response)
        body = parse(response.body)
        code = body['response_Code'] || body['responseCode']
        return body if response.is_a?(Net::HTTPSuccess) && (code.nil? || code.to_s == SUCCESS_CODE)

        reject!("refused: #{code || response.code}")
      end

      def parse(raw)
        parsed = JSON.parse(raw.to_s)
        parsed.is_a?(Hash) ? parsed : { 'reply' => parsed }
      rescue JSON::ParserError
        { 'reply' => raw.to_s.truncate(500) }
      end

      def reject!(detail)
        Rails.logger.warn("KuickPay send SMS request failed: #{detail}")
        raise PaymentCheckoutUnavailableError
      end
    end
  end
end

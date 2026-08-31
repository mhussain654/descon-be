# frozen_string_literal: true

module Payments
  module Providers
    class KuickpaySessionPayloadBuilder
      def initialize(configuration:, payment:, amount:, currency_code:)
        @configuration = configuration
        @payment = payment
        @amount = amount
        @currency_code = currency_code
      end

      def call
        base_payload.merge(signature:)
      end

      private

      def base_payload
        {
          companyid: @configuration.kuickpay_company_id,
          orderid: @payment.provider_order_id,
          amount: formatted_amount,
          amountPayable: formatted_amount,
          timestamp:,
          transactiondescription: "Descon onboarding fee #{@payment.public_id}",
          returnurl: @configuration.kuickpay_return_url,
          currency: @currency_code
        }
      end

      def signature
        data = [
          @configuration.kuickpay_company_id,
          @payment.provider_order_id,
          formatted_amount,
          formatted_amount,
          timestamp
        ].join('|')
        OpenSSL::HMAC.hexdigest('SHA256', @configuration.kuickpay_secured_key, data)
      end

      def timestamp
        @timestamp ||= Time.current.utc.strftime('%Y%m%d%H%M%S')
      end

      def formatted_amount
        @formatted_amount ||= format('%.2f', @amount)
      end
    end
  end
end

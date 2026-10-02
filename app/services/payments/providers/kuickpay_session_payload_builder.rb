# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'uri'
require 'cgi'

module Payments
  module Providers
    # Builds the POST /checkout/api/session request body per KuickPay's own
    # "KuickPay Merchant Integration Guide" (hosted checkout, distinct from
    # their BPS biller-inquiry API): companyid, orderid, amount,
    # amountPayable, timestamp, transactiondescription, returnurl, signature
    # -- no other fields are part of the documented contract, so none are
    # sent (in particular, no `currency` field -- KuickPay never asks for
    # one here; Payment's own currency_code is tracked internally only).
    #
    # `amountPayable` is currently always equal to `amount` -- there is no
    # documented Descon-side surcharge to add on top of the onboarding fee,
    # so inventing a different value would not be backed by real data.
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

      # The exact values sent for orderid/amount/amountPayable/timestamp and
      # the signature computed from them -- callers must persist this
      # verbatim (see the migration comment on
      # payments.provider_request_timestamp) so the KuickPay Status API can
      # later be called with byte-for-byte identical values, as their guide
      # requires.
      def request_snapshot
        {
          provider_request_timestamp: timestamp,
          provider_request_signature: signature,
          provider_amount_payable: formatted_amount
        }
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
          returnurl: return_url
        }
      end

      # Confirmed against a real sandbox return (2026-10-01): KuickPay's
      # actual return redirect carries no query params at all -- not
      # `orderid`, `status`, nor `sessionid`, despite their guide documenting
      # all three. So this app cannot rely on anything KuickPay adds to the
      # return request; it must be able to identify which payment a return
      # belongs to from the returnurl it itself sent, which is the one part
      # of this flow fully under our control regardless of what KuickPay
      # does or doesn't append on top. HostedCheckoutReturnsController reads
      # this same `orderid` query param back out.
      def return_url
        uri = URI.parse(@configuration.kuickpay_return_url)
        uri.query = [uri.query, "orderid=#{CGI.escape(@payment.provider_order_id)}"].compact.join('&')
        uri.to_s
      end

      # KuickPay's guide: "Construct the canonical string:
      # companyid|orderid|amount|amountPayable|timestamp. Hash it with your
      # SecuredKey as the HMAC key," with their own JS example rendering the
      # HMAC as Base64 (CryptoJS.enc.Base64) -- not hex.
      def signature
        data = [
          @configuration.kuickpay_company_id,
          @payment.provider_order_id,
          formatted_amount,
          formatted_amount,
          timestamp
        ].join('|')
        Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', @configuration.kuickpay_secured_key.to_s, data))
      end

      # KuickPay's guide only specifies "ISO 8601 formatted timestamp" --
      # Time#iso8601 on a UTC time renders e.g. "2026-09-28T15:30:00Z".
      def timestamp
        @timestamp ||= Time.current.utc.iso8601
      end

      def formatted_amount
        @formatted_amount ||= format('%.2f', @amount)
      end
    end
  end
end

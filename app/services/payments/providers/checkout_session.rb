# frozen_string_literal: true

module Payments
  module Providers
    CheckoutSession = Struct.new(
      :provider_code,
      :session_id,
      :checkout_url,
      :expires_at,
      # Only populated by adapters whose provider requires the exact
      # session-creation request to be replayable later (currently KuickPay
      # -- see KuickpaySessionPayloadBuilder#request_snapshot and
      # payments.provider_request_timestamp's migration comment). nil for
      # every other provider.
      :provider_request_timestamp,
      :provider_request_signature,
      :provider_amount_payable,
      keyword_init: true
    )
  end
end

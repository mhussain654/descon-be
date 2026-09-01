# frozen_string_literal: true

module Payments
  module Providers
    CheckoutSession = Struct.new(
      :provider_code,
      :session_id,
      :checkout_url,
      :expires_at,
      keyword_init: true
    )
  end
end

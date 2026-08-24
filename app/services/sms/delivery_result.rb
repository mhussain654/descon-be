# frozen_string_literal: true

module Sms
  # Return value of any Sms provider's #deliver. Mirrors the
  # Communication model's channel/status/provider_reference/error_code
  # shape used elsewhere in the app for outbound-message logging, so a
  # future caller that persists a Communication row from this result can
  # map the fields directly.
  DeliveryResult = Struct.new(:success, :provider_reference, :error_code, keyword_init: true) do
    def success?
      success
    end
  end
end

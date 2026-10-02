# frozen_string_literal: true

module Payments
  module Providers
    # The raw outcome of a provider's Verify Status call -- kept separate from
    # Notification (which represents a *confidently parsed* payment outcome)
    # because KuickPay's Status API response shape is not documented anywhere
    # in their integration guide. `body` is whatever JSON.parse returned, or
    # the raw response string if it wasn't valid JSON -- callers must treat it
    # defensively, never assume a particular shape.
    StatusCheckResponse = Struct.new(:http_status, :body, keyword_init: true)
  end
end

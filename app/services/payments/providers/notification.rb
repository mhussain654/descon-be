# frozen_string_literal: true

module Payments
  module Providers
    Notification = Struct.new(
      :provider_code,
      :event_source,
      :event_key,
      :provider_order_id,
      :provider_transaction_id,
      :provider_status_code,
      :provider_response_code,
      :amount,
      :currency_code,
      :occurred_at,
      :payload,
      keyword_init: true
    ) do
      def success? = provider_status_code == 'SUCCESS'

      def failed? = provider_status_code == 'FAILED'

      def cancelled? = provider_status_code == 'CANCELLED'
    end
  end
end

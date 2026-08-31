# frozen_string_literal: true

module Payments
  class NotificationEventRecorder < ApplicationService
    def initialize(payment:, assignment:, notification:, request_id:)
      @payment = payment
      @assignment = assignment
      @notification = notification
      @request_id = request_id
    end

    def call
      PaymentEvent.create!(event_attributes)
    end

    private

    def event_attributes
      base_attributes.merge(provider_attributes).merge(
        occurred_at: @notification.occurred_at,
        processed_at: Time.current,
        payload: @notification.payload
      )
    end

    def base_attributes
      {
        payment: @payment,
        candidate_assignment: @assignment,
        request_id: @request_id
      }
    end

    def provider_attributes
      {
        provider_code: @notification.provider_code,
        event_source: @notification.event_source,
        event_type: event_type,
        event_key: @notification.event_key,
        provider_order_id: @notification.provider_order_id,
        provider_transaction_id: @notification.provider_transaction_id,
        provider_status_code: @notification.provider_status_code
      }
    end

    def event_type
      case @notification.provider_status_code
      when 'SUCCESS' then 'payment_succeeded'
      when 'CANCELLED' then 'payment_cancelled'
      else 'payment_failed'
      end
    end
  end
end

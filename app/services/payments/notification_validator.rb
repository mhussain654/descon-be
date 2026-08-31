# frozen_string_literal: true

module Payments
  class NotificationValidator < ApplicationService
    def initialize(payment:, notification:)
      @payment = payment
      @notification = notification
    end

    def call
      validate_order!
      validate_amount!
      validate_currency!
      validate_paid_payment_conflict!
    end

    private

    def validate_order!
      return if @payment.provider_order_id == @notification.provider_order_id

      raise PaymentNotificationMismatchError.new(
        field: 'payment_notification.orderid',
        details: mismatch_details
      )
    end

    def validate_amount!
      return if @payment.amount == @notification.amount

      raise PaymentNotificationMismatchError.new(
        field: 'payment_notification.amount',
        details: mismatch_details
      )
    end

    def validate_currency!
      return if @notification.currency_code.blank? || @payment.currency_code == @notification.currency_code

      raise PaymentNotificationMismatchError.new(
        field: 'payment_notification.currency',
        details: mismatch_details
      )
    end

    def validate_paid_payment_conflict!
      return unless @payment.paid? && @notification.success?
      return if consistent_success_replay?

      raise PaymentNotificationConflictError.new(details: mismatch_details)
    end

    def consistent_success_replay?
      @payment.external_reference == @notification.provider_transaction_id &&
        @payment.provider_status_code == @notification.provider_status_code &&
        @payment.amount == @notification.amount &&
        currency_matches?
    end

    def currency_matches?
      @notification.currency_code.blank? || @payment.currency_code == @notification.currency_code
    end

    def mismatch_details
      { provider_order_id: @notification.provider_order_id }
    end
  end
end

# frozen_string_literal: true

module Payments
  # Calls the provider's Verify Status API for one payment (the 4th step of
  # KuickPay's documented hosted-checkout flow: Create Session -> Redirect ->
  # Handle Return -> Verify Status) and records what came back.
  #
  # Every call is recorded as an append-only PaymentEvent carrying the raw
  # response body, regardless of whether it can be confidently interpreted --
  # KuickPay's Status API response shape is not documented anywhere in their
  # integration guide, so this is deliberately the source of truth to inspect
  # and share with KuickPay (see Payments::Providers::
  # KuickpayHostedCheckoutAdapter#verify_status, which also logs the full
  # request/response). Only applies a state change to the Payment when the
  # response can be confidently read as carrying a real outcome -- an
  # unrecognized shape is recorded but never guessed at.
  #
  # Two real shapes confirmed against the sandbox (2026-10-01), both lacking
  # a `responseData` wrapper (unlike Create Session's response):
  #   not found: {"responseCode":"01","status":"failure","responseDescription":"Session not found"}
  #   found:     {"responseCode":"00","status":true,"sessionID":"...",
  #               "gatewayResponse":{"paymentStatus":"00","paymentID":"..."}}
  # The top-level `responseCode`/`status` only say whether KuickPay found the
  # session (mirroring Create Session's own `responseCode == '00'`
  # convention) -- they are NOT the payment outcome and must not be read as
  # one. The actual payment result lives nested under `gatewayResponse`.
  # Conflating the two was a real bug caught live: a genuinely successful
  # payment (gatewayResponse.paymentStatus == '00') was being marked
  # `failed` because the top-level `status: true` boolean got stringified to
  # "TRUE", which matches neither "SUCCESS" nor "CANCELLED" in Notification.
  # Only `gatewayResponse.paymentStatus == '00'` is confirmed to mean success
  # so far -- every other gatewayResponse shape (or its absence) is left
  # unrecognized rather than guessed as a failure, since no real failed-
  # payment response has been observed yet to confirm that shape.
  class VerifyPaymentStatusService < ApplicationService
    def initialize(payment:, request_id:)
      @payment = payment
      @request_id = request_id
    end

    def call
      response = provider.verify_status(payment: @payment)
      record_status_check_event!(response)
      apply_if_recognizable!(response)
      response
    end

    private

    def provider
      Payments::ProviderRegistry.fetch(@payment.provider_code)
    end

    def record_status_check_event!(response)
      PaymentEvent.create!(status_check_event_attributes(response))
    end

    def status_check_event_attributes(response)
      status_check_event_identity.merge(
        occurred_at: Time.current,
        processed_at: Time.current,
        request_id: @request_id,
        payload: { 'http_status' => response.http_status, 'body' => response.body }
      )
    end

    def status_check_event_identity
      {
        payment: @payment,
        candidate_assignment: @payment.candidate_assignment,
        provider_code: @payment.provider_code,
        event_source: 'status_check',
        event_type: 'status_checked',
        event_key: "status_check:#{@payment.provider_order_id}:#{SecureRandom.uuid}",
        provider_order_id: @payment.provider_order_id
      }
    end

    # Only reads the response if it confidently matches the one confirmed
    # "payment succeeded" shape -- an unrecognized response (session not
    # found, a malformed body, an unconfirmed gatewayResponse shape) is left
    # alone: the Payment stays exactly as it was, never guessed into a wrong
    # state from an unconfirmed contract.
    def apply_if_recognizable!(response)
      notification = notification_from(response)
      return if notification.nil?

      CandidateAssignment.transaction { apply_notification!(notification) }
    end

    def notification_from(response)
      return nil unless response.body.is_a?(Hash)

      data = response.body
      return nil unless session_found?(data)

      gateway = data['gatewayResponse']
      return nil unless gateway.is_a?(Hash) && gateway['paymentStatus'] == '00'

      build_notification(data:, gateway:)
    end

    # Mirrors Create Session's own `responseCode == '00'` success convention
    # -- this only confirms KuickPay found the session, not that the payment
    # succeeded (see the class-level comment).
    def session_found?(data)
      data['responseCode'] == '00'
    end

    def build_notification(data:, gateway:)
      Payments::Providers::Notification.new(notification_attributes(data:, gateway:))
    end

    def notification_attributes(data:, gateway:)
      notification_identity(data:, gateway:).merge(
        provider_status_code: 'SUCCESS',
        provider_response_code: gateway['paymentStatus'],
        # The Status API response carries no amount field at all (confirmed
        # shape) -- comparing the payment's own amount against itself keeps
        # NotificationValidator's amount check a no-op here.
        amount: @payment.amount,
        currency_code: nil,
        occurred_at: Time.current,
        payload: data
      )
    end

    def notification_identity(data:, gateway:)
      {
        provider_code: @payment.provider_code,
        event_source: 'status_check',
        event_key: "status_check_applied:#{@payment.provider_order_id}:#{SecureRandom.uuid}",
        provider_order_id: data['orderID'] || data['orderid'] || @payment.provider_order_id,
        provider_transaction_id: gateway['paymentID']
      }
    end

    def apply_notification!(notification)
      payment = Payment.lock.find(@payment.id)
      assignment = CandidateAssignment.lock.find(payment.candidate_assignment_id)
      candidate = Candidate.lock.find(assignment.candidate_id)

      Payments::NotificationValidator.call(payment:, notification:)
      Payments::PaymentStateApplier.call(payment:, assignment:, candidate:, notification:, request_id: @request_id)
    end
  end
end

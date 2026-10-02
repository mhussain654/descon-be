# frozen_string_literal: true

module Payments
  class CheckoutSessionPersister < ApplicationService
    def initialize(payment:, assignment:, candidate:, request_id:, session:)
      @payment = payment
      @assignment = assignment
      @candidate = candidate
      @request_id = request_id
      @session = session
    end

    def call
      persist_session!
      mark_assignment_updated!
      record_checkout_audit!
      record_session_created_event!
    end

    private

    def persist_session!
      @payment.update!(
        provider_session_id: @session.session_id,
        checkout_url: @session.checkout_url,
        checkout_expires_at: @session.expires_at,
        # nil unless the provider populates these -- see CheckoutSession's
        # field comment.
        provider_request_timestamp: @session.provider_request_timestamp,
        provider_request_signature: @session.provider_request_signature,
        provider_amount_payable: @session.provider_amount_payable
      )
    end

    def mark_assignment_updated!
      @assignment.update!(updated_at: Time.current)
    end

    def record_checkout_audit!
      Payments::AuditRecorder.call(
        action: :checkout_initiated,
        payment: @payment,
        candidate: @candidate,
        assignment: @assignment,
        request_id: @request_id,
        metadata: { checkout_expires_at: @session.expires_at.utc.iso8601 }
      )
    end

    # Records the provider's full, unmodified session-creation response as a
    # durable, queryable PaymentEvent -- not just a Rails log line -- so it
    # can be retrieved later (e.g. to share with the provider while
    # confirming contract details). Only populated for providers that
    # return one (currently KuickPay -- see CheckoutSession#raw_response).
    def record_session_created_event!
      return if @session.raw_response.blank?

      PaymentEvent.create!(session_created_event_attributes)
    end

    def session_created_event_attributes
      session_created_event_identity.merge(
        occurred_at: Time.current,
        processed_at: Time.current,
        request_id: @request_id,
        payload: { 'body' => @session.raw_response }
      )
    end

    def session_created_event_identity
      {
        payment: @payment,
        candidate_assignment: @assignment,
        provider_code: @payment.provider_code,
        event_source: 'create_session',
        event_type: 'session_created',
        event_key: "session_created:#{@payment.provider_order_id}:#{SecureRandom.uuid}",
        provider_order_id: @payment.provider_order_id
      }
    end
  end
end

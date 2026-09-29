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
  end
end

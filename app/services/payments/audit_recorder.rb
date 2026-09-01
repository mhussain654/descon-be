# frozen_string_literal: true

module Payments
  class AuditRecorder < ApplicationService
    Params = Struct.new(:action, :payment, :candidate, :assignment, :request_id, :actor, :metadata, keyword_init: true)

    ACTION_CODES = {
      checkout_initiated: 'candidate_payment_checkout_initiated',
      paid: 'candidate_payment_paid',
      failed: 'candidate_payment_failed',
      cancelled: 'candidate_payment_cancelled'
    }.freeze

    def initialize(**params) = @params = Params.new(actor: nil, metadata: {}, **params)

    def call
      AuditEvent.create!(audit_attributes)
    end

    private

    def audit_attributes
      base_audit_attributes.merge(metadata:, occurred_at: Time.current)
    end

    def metadata
      base_metadata.merge(@params.metadata)
    end

    def base_audit_attributes
      {
        actor: @params.actor,
        candidate: @params.candidate,
        candidate_assignment: @params.assignment,
        entity_type: 'Payment',
        entity_id: @params.payment.id,
        action_code: ACTION_CODES.fetch(@params.action),
        request_id: @params.request_id
      }
    end

    def base_metadata
      {
        candidate_public_id: @params.candidate.public_id,
        candidate_assignment_public_id: @params.assignment.public_id,
        payment_public_id: @params.payment.public_id,
        provider_code: @params.payment.provider_code,
        payment_status_code: @params.payment.status_code
      }.compact
    end
  end
end

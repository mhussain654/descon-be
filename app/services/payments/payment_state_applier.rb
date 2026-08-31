# frozen_string_literal: true

module Payments
  class PaymentStateApplier < ApplicationService
    def initialize(payment:, assignment:, candidate:, notification:, request_id:)
      @payment = payment
      @assignment = assignment
      @candidate = candidate
      @notification = notification
      @request_id = request_id
    end

    def call
      return apply_success! if @notification.success?
      return apply_non_success!('cancelled') if @notification.cancelled?

      apply_non_success!('failed')
    end

    private

    def apply_success!
      return if @payment.paid?

      @payment.update!(success_attributes)
      mark_assignment_updated!
      record_payment_audit!(:paid)
      ensure_fee_workflow!
    end

    def apply_non_success!(status_code)
      return if @payment.paid?

      @payment.update!(non_success_attributes(status_code))
      mark_assignment_updated!
      record_payment_audit!(status_code.to_sym)
    end

    def ensure_fee_workflow!
      @assignment.reload
      transition_to_fee_pending!
      transition_to_fee_paid! if @assignment.current_workflow_stage.code == 'fee_pending'
    end

    def transition_to_fee_pending!
      return unless @assignment.current_workflow_stage.code == 'verified'

      CandidateWorkflows::TransitionService.call(
        actor: nil,
        candidate: @candidate,
        to_stage_code: 'fee_pending',
        request_id: "#{@request_id}:fee_pending",
        validate_permissions: false
      )
      @assignment.reload
    end

    def transition_to_fee_paid!
      CandidateWorkflows::TransitionService.call(
        actor: nil,
        candidate: @candidate,
        to_stage_code: 'fee_paid',
        request_id: "#{@request_id}:fee_paid",
        validate_permissions: false
      )
    end

    def success_attributes
      {
        status_code: 'paid',
        external_reference: @notification.provider_transaction_id,
        provider_transaction_id: @notification.provider_transaction_id,
        provider_status_code: @notification.provider_status_code,
        provider_response_code: @notification.provider_response_code,
        paid_at: @notification.occurred_at,
        last_provider_event_at: @notification.occurred_at
      }
    end

    def non_success_attributes(status_code)
      {
        status_code:,
        provider_transaction_id: @notification.provider_transaction_id,
        provider_status_code: @notification.provider_status_code,
        provider_response_code: @notification.provider_response_code,
        last_provider_event_at: @notification.occurred_at
      }
    end

    def mark_assignment_updated!
      @assignment.update!(updated_at: Time.current)
    end

    def record_payment_audit!(action)
      Payments::AuditRecorder.call(
        action:,
        payment: @payment,
        candidate: @candidate,
        assignment: @assignment,
        request_id: @request_id,
        metadata: { provider_status_code: @notification.provider_status_code }
      )
    end
  end
end

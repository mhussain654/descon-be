# frozen_string_literal: true

module Payments
  class NotificationProcessor < ApplicationService
    def initialize(provider_code:, event_source:, params:, request_id:)
      @provider_code = provider_code
      @event_source = event_source
      @params = params.to_h
      @request_id = request_id
    end

    def call
      notification = provider.parse_notification!(event_source: @event_source, params: @params)
      CandidateAssignment.transaction { process_notification(notification) }
    rescue PaymentNotificationConflictError => e
      record_conflict_audit_for(notification)
      raise e
    rescue Payments::ProviderNotConfiguredError
      raise PaymentCheckoutUnavailableError
    end

    private

    def process_notification(notification)
      payment, assignment, candidate = locked_payment_context(notification)
      return result(payment:, candidate:, replayed: true) if duplicate_event?(notification:)

      Payments::NotificationValidator.call(payment:, notification:)
      Payments::PaymentStateApplier.call(payment:, assignment:, candidate:, notification:, request_id: @request_id)
      Payments::NotificationEventRecorder.call(payment:, assignment:, notification:, request_id: @request_id)
      result(payment:, candidate:)
    end

    def locked_payment_context(notification)
      payment = Payment.lock.find_by!(
        provider_order_id: notification.provider_order_id,
        provider_code: notification.provider_code
      )
      assignment = CandidateAssignment.lock.find(payment.candidate_assignment_id)
      candidate = Candidate.lock.find(assignment.candidate_id)
      [payment, assignment, candidate]
    end

    def duplicate_event?(notification:)
      PaymentEvent.find_by(provider_code: notification.provider_code, event_key: notification.event_key)
    end

    def record_conflict_audit_for(notification)
      payment = conflicting_payment_for(notification)
      return if payment.blank?

      Payments::AuditRecorder.call(
        action: :failed,
        payment:,
        candidate: payment.candidate_assignment.candidate,
        assignment: payment.candidate_assignment,
        request_id: @request_id,
        metadata: conflict_metadata(notification)
      )
    end

    def conflicting_payment_for(notification)
      Payment.find_by(provider_code: notification.provider_code, provider_order_id: notification.provider_order_id)
    end

    def conflict_metadata(notification)
      {
        conflict: true,
        provider_order_id: notification.provider_order_id,
        provider_status_code: notification.provider_status_code
      }
    end

    def provider
      @provider ||= Payments::ProviderRegistry.fetch(@provider_code)
    end

    def result(payment:, candidate:, replayed: false)
      candidate.reload
      {
        payment: payment.reload,
        eligibility: Payments::EligibilityService.call(candidate:, provider_code: payment.provider_code),
        snapshot: CandidateWorkflows::StateSnapshotService.call(candidate:),
        replayed:
      }
    end
  end
end

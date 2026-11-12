# frozen_string_literal: true

module Payments
  # Runs when a candidate reaches the fee stage (Payments::IssueFeeVoucherJob), so the candidate never has to
  # ask for a code: issues their KuickPay voucher, has KuickPay text them the code, then queues our own
  # "medical cleared, pay your fee" SMS, which tells them the code was sent. Safe to run again: the open voucher
  # is reused, KuickPay's SMS goes out once per voucher and our SMS once per stage entry. A candidate who has
  # moved on, paid already or cannot pay by voucher gets nothing; a KuickPay failure raises
  # PaymentCheckoutUnavailableError for the job to retry.
  class IssueFeeVoucherService < ApplicationService
    SMS_EVENT_TYPE = 'voucher_sms_sent'
    FEE_MESSAGE_CODE = 'fee_pending'

    def initialize(candidate_assignment_id:, history_entry_id:)
      @assignment = CandidateAssignment.find_by(id: candidate_assignment_id)
      @history_entry_id = history_entry_id
    end

    def call
      return unless issuable?

      payment = open_voucher
      return if payment.blank?

      send_code_sms!(payment)
      CandidateSms::ScheduleDelivery.call(assignment: @assignment, message_code: FEE_MESSAGE_CODE,
                                          dedupe_key: "#{FEE_MESSAGE_CODE}:#{@history_entry_id}")
    end

    private

    def issuable?
      return false if @assignment.blank? || candidate.current_assignment != @assignment || !candidate.active?

      provider.available? && AppFeatureSetting.enabled?(:voucher_payment)
    end

    # An existing unpaid voucher (the candidate asked for one already) is returned, not replaced.
    def open_voucher
      Payments::CreateVoucherService.call(candidate:, request_id:).fetch(:payment)
    rescue PaymentNotEligibleError, InactiveAccountError, NoCurrentAssignmentError
      nil
    end

    def send_code_sms!(payment)
      event_key = "#{SMS_EVENT_TYPE}:#{payment.provider_order_id}"
      return if PaymentEvent.exists?(provider_code: payment.provider_code, event_key:)

      reply = provider.send_voucher_sms(payment:, candidate:)
      record_sms_event!(payment:, event_key:, reply:)
    end

    def record_sms_event!(payment:, event_key:, reply:)
      PaymentEvent.create!(
        payment:, candidate_assignment: @assignment, provider_code: payment.provider_code,
        event_source: 'send_voucher_sms', event_type: SMS_EVENT_TYPE, event_key:,
        provider_order_id: payment.provider_order_id, occurred_at: Time.current, processed_at: Time.current,
        request_id:, payload: { 'body' => reply }
      )
    end

    def request_id = "fee_voucher:#{@history_entry_id}"
    def candidate = @assignment.candidate
    def provider = @provider ||= Payments::ProviderRegistry.fetch('kuickpay_voucher')
  end
end

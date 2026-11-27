# frozen_string_literal: true

module Payments
  # Replaces a candidate's unpaid KuickPay voucher with a new one and has KuickPay text them the new Kuickpay ID
  # (rake payments:kuickpay:reissue_voucher). For vouchers issued before the Kuickpay ID was built from the
  # registration number (Nov 2026): those carry KuickPay's reference number, which banking and wallet apps
  # cannot find. The old payment is cancelled (and audited) in the same transaction that issues the new one,
  # so a failed KuickPay call leaves the old voucher as it was. The old voucher stays on KuickPay's side;
  # delete it in KuickPay's portal so it cannot be paid by mistake.
  class ReissueVoucherService < ApplicationService
    Result = Data.define(:old_payment, :new_payment, :sms_sent)

    def initialize(payment:, request_id: "reissue_voucher:#{SecureRandom.uuid}")
      @payment = payment
      @request_id = request_id
    end

    def call
      validate!
      new_payment = CandidateAssignment.transaction do
        cancel_old_payment!
        Payments::CreateVoucherService.call(candidate:, request_id: @request_id).fetch(:payment)
      end
      Result.new(old_payment: @payment.reload, new_payment:, sms_sent: send_sms!(new_payment))
    end

    private

    def validate!
      raise ArgumentError, 'not a KuickPay voucher payment' unless @payment.provider_code == provider.provider_code
      raise ArgumentError, "payment is #{@payment.status_code}, only an unpaid voucher can be replaced" unless
        @payment.checkout_pending?
    end

    def cancel_old_payment!
      @payment.lock!
      @payment.update!(status_code: 'cancelled')
      Payments::AuditRecorder.call(
        action: :cancelled, payment: @payment, candidate:, assignment: @payment.candidate_assignment,
        request_id: @request_id, metadata: { reason: 'voucher_reissued', voucher_number: @payment.voucher_number }
      )
    end

    # The new voucher already exists by now, so a refused SMS is reported, not raised: the voucher stays valid
    # and the candidate can still see its Kuickpay ID in the app.
    def send_sms!(payment)
      record_sms_event!(payment, provider.send_voucher_sms(payment:, candidate:))
      true
    rescue PaymentCheckoutUnavailableError
      false
    end

    def record_sms_event!(payment, reply)
      event_type = Payments::IssueFeeVoucherService::SMS_EVENT_TYPE
      PaymentEvent.create!(
        payment:, candidate_assignment: payment.candidate_assignment, provider_code: payment.provider_code,
        event_source: 'send_voucher_sms', event_type:, event_key: "#{event_type}:#{payment.provider_order_id}",
        provider_order_id: payment.provider_order_id, occurred_at: Time.current, processed_at: Time.current,
        request_id: @request_id, payload: { 'body' => reply }
      )
    end

    def candidate = @payment.candidate_assignment.candidate
    def provider = @provider ||= Payments::ProviderRegistry.fetch('kuickpay_voucher')
  end
end

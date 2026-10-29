# frozen_string_literal: true

module Payments
  # Gives the candidate a KuickPay voucher (payment) number for their fee, to pay
  # from a wallet or bank app. Idempotent: while an unpaid, unexpired voucher exists
  # it is returned, never a second one. It does not matter if a card checkout is
  # open too -- the candidate chooses (see Payments::OpenPayments); refused only if
  # the fee has already been paid. The provider call runs inside the same
  # transaction as the local records, so a failed call leaves nothing behind.
  class CreateVoucherService < ApplicationService
    TIME_ZONE = 'Asia/Karachi'

    def initialize(candidate:, request_id:)
      @candidate = candidate
      @request_id = request_id
      @configuration = Payments::Configuration.new
    end

    def call
      raise PaymentCheckoutUnavailableError unless provider.available? && AppFeatureSetting.enabled?(:voucher_payment)

      CandidateAssignment.transaction { execute }
    end

    private

    def execute
      candidate, assignment = locked_candidate_and_assignment
      ensure_eligible!(candidate:)

      existing = Payments::OpenPayments.voucher(assignment)
      return response_for(existing, replayed: true) if existing.present?

      payment = create_payment!(assignment:)
      issue_voucher!(payment:, candidate:, assignment:)
      response_for(payment)
    end

    def locked_candidate_and_assignment
      candidate = Candidate.lock.find(@candidate.id)
      raise InactiveAccountError unless candidate.active?

      assignment = candidate.current_assignment
      raise NoCurrentAssignmentError if assignment.blank?

      assignment.lock!
      [candidate, assignment]
    end

    def ensure_eligible!(candidate:)
      eligibility = Payments::EligibilityService.call(candidate:, provider_code: provider.provider_code)
      return if eligibility.eligible

      raise PaymentNotEligibleError.new(details: { blocking_reasons: eligibility.blocking_reasons })
    end

    def create_payment!(assignment:)
      assignment.payments.create!(
        payment_type_code: 'onboarding_fee', status_code: 'checkout_pending',
        amount: Payments::FeeResolver.amount(assignment), currency_code: @configuration.currency_code,
        provider_code: provider.provider_code,
        provider_order_id: "PAY-#{assignment.reference_number}-#{SecureRandom.hex(6).upcase}"
      )
    end

    def issue_voucher!(payment:, candidate:, assignment:)
      expires_on = Time.current.in_time_zone(TIME_ZONE).to_date + @configuration.voucher_valid_days
      voucher = provider.create_voucher(payment:, candidate:, expires_on:)
      expires_at = expires_on.in_time_zone(TIME_ZONE).end_of_day
      payment.update!(voucher_number: voucher.consumer_number, checkout_expires_at: expires_at)
      assignment.update!(updated_at: Time.current)
      record_audit!(payment:, assignment:, expires_at:)
      record_event!(payment:, assignment:, voucher:)
    end

    def record_audit!(payment:, assignment:, expires_at:)
      Payments::AuditRecorder.call(
        action: :checkout_initiated, payment:, candidate: @candidate, assignment:, request_id: @request_id,
        metadata: { method: 'voucher', voucher_expires_at: expires_at.utc.iso8601 }
      )
    end

    # The provider's full response is kept as a durable event, like the card session's.
    def record_event!(payment:, assignment:, voucher:)
      PaymentEvent.create!(
        payment:, candidate_assignment: assignment, provider_code: payment.provider_code,
        event_source: 'create_voucher', event_type: 'voucher_created',
        event_key: "voucher_created:#{payment.provider_order_id}:#{SecureRandom.uuid}",
        provider_order_id: payment.provider_order_id, occurred_at: Time.current, processed_at: Time.current,
        request_id: @request_id, payload: { 'body' => voucher.raw_response }
      )
    end

    def response_for(payment, replayed: false)
      {
        payment: payment.reload,
        eligibility: Payments::EligibilityService.call(candidate: @candidate, provider_code: provider.provider_code),
        replayed:
      }
    end

    def provider
      @provider ||= Payments::ProviderRegistry.fetch('kuickpay_voucher')
    end
  end
end

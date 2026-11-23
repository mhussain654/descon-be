# frozen_string_literal: true

module Admin
  module Payments
    # Lets a developer mark a candidate's onboarding fee paid when KuickPay took
    # the money but the system never heard about it (the voucher settlement job
    # missed it, or the card result never came back), so the candidate moves on
    # straight away instead of waiting.
    #
    # Only for a candidate at Fee Pending who has not paid yet. Their open
    # payment (voucher or card checkout) is marked paid when there is one;
    # otherwise a manual payment is recorded for the current fee. Either way it
    # carries the KuickPay reference, the paid day, who recorded it and why, an
    # append-only PaymentEvent and an audit event, and the candidate moves to
    # Fee Paid exactly as a provider-confirmed payment would. A later KuickPay
    # result for the same payment is ignored, since it is already paid.
    class ManualPaymentService < ApplicationService
      PAYMENT_TYPE = 'onboarding_fee'
      MANUAL_PROVIDER = 'manual'
      EVENT_TYPE = 'payment_marked_paid'
      REFERENCE_MAX_LENGTH = 100
      REASON_MAX_LENGTH = 500
      # Fees are paid in Pakistan, so the paid day is a calendar day there.
      TIME_ZONE = 'Asia/Karachi'

      # `values` holds the form: `reference`, `paid_on` (YYYY-MM-DD), `reason` and,
      # from a payment's own page, `payment_id` (that open payment's public id).
      def initialize(actor:, candidate:, values:, request_id:)
        @actor = actor
        @candidate = candidate
        @reference, @paid_on, @reason, @payment_id =
          values.values_at(:reference, :paid_on, :reason, :payment_id).map { |value| value.to_s.strip }
        @request_id = request_id
      end

      def call
        raise InactiveAccountError unless @actor&.active_staff_account?
        raise ForbiddenError unless @actor.permission?('record_manual_payment')

        validate_input!
        CandidateAssignment.transaction { record! }
      end

      private

      def record!
        lock_assignment!
        payment = open_payment || new_payment
        validate_reference_unused!(payment)
        payment.update!(status_code: 'paid', paid_at:, external_reference: @reference, recorded_by: @actor,
                        note: @reason)
        @assignment.update!(updated_at: Time.current)
        record_event!(payment)
        record_audit!(payment)
        move_to_fee_paid!
        payment
      end

      def lock_assignment!
        assignment_id = @candidate.current_assignment&.id
        @assignment = CandidateAssignment.lock.find_by(id: assignment_id)
        Candidate.lock.find(@candidate.id)
        raise ManualPaymentNotAllowedError unless fee_pending?
      end

      def fee_pending?
        @assignment.present? && @assignment.current_workflow_stage.code == 'fee_pending' &&
          !@assignment.payments.exists?(payment_type_code: PAYMENT_TYPE, status_code: 'paid')
      end

      # The named payment must be one of the candidate's open fee payments.
      def open_payment
        open = @assignment.payments.where(payment_type_code: PAYMENT_TYPE, status_code: 'checkout_pending')
        return open.latest_first.lock.first if @payment_id.blank?

        open.lock.find_by(public_id: @payment_id) || raise(ManualPaymentNotAllowedError)
      end

      def new_payment
        @assignment.payments.new(payment_type_code: PAYMENT_TYPE, provider_code: MANUAL_PROVIDER,
                                 amount: ::Payments::FeeResolver.amount(@assignment),
                                 currency_code: ::Payments::Configuration.new.currency_code)
      end

      def validate_input!
        invalid!('reference', 'manual_payment_reference_required') if @reference.blank?
        invalid!('reference', 'manual_payment_reference_too_long') if @reference.length > REFERENCE_MAX_LENGTH
        invalid!('reason', 'manual_payment_reason_required') if @reason.blank?
        invalid!('reason', 'manual_payment_reason_too_long') if @reason.length > REASON_MAX_LENGTH
        invalid!('paid_on', 'manual_payment_paid_on_invalid') if paid_day.nil? || paid_day > today
      end

      def validate_reference_unused!(payment)
        return unless Payment.where(external_reference: @reference).where.not(id: payment.id).exists?

        invalid!('reference', 'manual_payment_reference_taken')
      end

      def invalid!(field, key)
        raise ValidationError.new(field: "manual_payment.#{field}", message: I18n.t("api.errors.#{key}"))
      end

      def paid_day
        @paid_day ||= Date.iso8601(@paid_on)
      rescue Date::Error
        nil
      end

      def today = Time.current.in_time_zone(TIME_ZONE).to_date

      # Now for today; midday in Pakistan for an earlier day, so it sits safely inside that day.
      def paid_at
        return Time.current if paid_day == today

        Time.find_zone!(TIME_ZONE).local(paid_day.year, paid_day.month, paid_day.day, 12)
      end

      def record_event!(payment)
        PaymentEvent.create!(
          payment:, candidate_assignment: @assignment, actor: @actor,
          provider_code: payment.provider_code.presence || MANUAL_PROVIDER, event_source: 'staff_manual',
          event_type: EVENT_TYPE, event_key: "#{EVENT_TYPE}:#{payment.public_id}",
          provider_order_id: payment.provider_order_id, provider_transaction_id: @reference,
          occurred_at: payment.paid_at, processed_at: Time.current, request_id: @request_id,
          payload: { reference: @reference, paid_on: paid_day.iso8601, reason: @reason }
        )
      end

      def record_audit!(payment)
        ::Payments::AuditRecorder.call(
          action: :marked_paid, payment:, candidate: @candidate, assignment: @assignment,
          request_id: @request_id, actor: @actor, metadata: { reference: @reference, paid_on: paid_day.iso8601 }
        )
      end

      # The same move a provider-confirmed payment makes (Payments::PaymentStateApplier).
      def move_to_fee_paid!
        CandidateWorkflows::TransitionService.call(actor: @actor, candidate: @candidate, to_stage_code: 'fee_paid',
                                                   request_id: "#{@request_id}:fee_paid", validate_permissions: false)
        CandidateWorkflows::AutomaticTransitionService.call(candidate: @candidate, event: :fee_paid,
                                                            request_id: "#{@request_id}:after_fee_paid")
      end
    end
  end
end

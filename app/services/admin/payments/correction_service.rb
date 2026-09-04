# frozen_string_literal: true

module Admin
  module Payments
    # Applies a staff-submitted correction to one payment. Deliberately
    # narrow in what it allows -- this is a correction, not a general
    # payment-editing tool, and it must never let a correction stand in for
    # real provider confirmation (ticket: "Never ... infer provider success
    # from frontend data").
    #
    # `field` is one of ALLOWED_FIELDS, or blank for a "note-only" resolution
    # (investigated a finding, no field was actually wrong). `status_code`
    # may only move to `paid` when the correction targets an *open*
    # `terminal_event_conflict` finding on this same payment -- that finding
    # code only ever exists when a real `payment_succeeded` PaymentEvent is
    # already on record (Payments::ReconciliationService), so approving it is
    # applying already-known provider truth, never staff say-so. Every other
    # status transition allowed here (`checkout_pending` -> `failed`/
    # `cancelled`) is administrative housekeeping (closing out an abandoned
    # checkout), not a claim about provider outcome.
    #
    # Stale-update protection mirrors Admin::ReferenceData::MutationService:
    # the caller echoes back the `updated_at` it last fetched
    # (`expected_updated_at`); a mismatch means someone else changed this
    # payment in the meantime, so the correction is rejected as stale rather
    # than silently overwriting it.
    # rubocop:disable Metrics/ClassLength
    class CorrectionService < ApplicationService
      ALLOWED_FIELDS = %w[external_reference paid_at status_code].freeze
      ALLOWED_STATUS_TRANSITIONS = [%w[checkout_pending failed], %w[checkout_pending cancelled]].freeze
      EVIDENCE_BACKED_STATUS_TRANSITIONS = { 'paid' => 'terminal_event_conflict' }.freeze

      Params = Struct.new(
        :actor, :payment, :reason, :expected_updated_at, :finding_id, :field, :value, :request_id,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(**params)
      end

      def call
        validate_actor!
        validate_reason!

        Payment.transaction { apply! }
      end

      private

      def apply!
        @payment = @params.payment.lock!
        validate_staleness!
        @finding = locate_finding
        @previous_value = current_field_value
        apply_correction!
        @finding&.resolve!(by: @params.actor, note: @params.reason)
        record_event!
        record_audit!
        @payment
      end

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_payments')
      end

      def validate_reason!
        return if @params.reason.to_s.strip.present?

        raise ValidationError.new(field: 'correction.reason',
                                  message: I18n.t('api.errors.payment_correction_reason_required'))
      end

      def validate_staleness!
        if @params.expected_updated_at.blank?
          raise ValidationError.new(field: 'correction.expected_updated_at',
                                    message: I18n.t('api.errors.validation_failed'))
        end

        expected = Time.iso8601(@params.expected_updated_at.to_s)
        raise StalePaymentError unless expected.to_i == @payment.updated_at.to_i
      rescue ArgumentError
        raise ValidationError.new(field: 'correction.expected_updated_at',
                                  message: I18n.t('api.errors.validation_failed'))
      end

      def locate_finding
        return nil if @params.finding_id.blank?

        finding = @payment.payment_reconciliation_findings.find_by(public_id: @params.finding_id)
        if finding.blank?
          raise ValidationError.new(field: 'correction.finding_id',
                                    message: I18n.t('api.errors.validation_failed'))
        end
        raise PaymentCorrectionNotAllowedError.new(field: 'correction.finding_id') if finding.resolved?

        finding
      end

      def current_field_value
        return nil if @params.field.blank?

        @payment.public_send(@params.field)&.to_s
      end

      def apply_correction!
        validate_action_requested!
        return if @params.field.blank?

        unless ALLOWED_FIELDS.include?(@params.field)
          raise PaymentCorrectionNotAllowedError.new(field: 'correction.field')
        end

        send(:"apply_#{@params.field}!")
      end

      def validate_action_requested!
        return if @params.field.present? || @params.finding_id.present?

        raise ValidationError.new(field: 'correction.field', message: I18n.t('api.errors.validation_failed'))
      end

      def apply_external_reference!
        value = @params.value.to_s.strip
        if value.blank?
          raise ValidationError.new(field: 'correction.value',
                                    message: I18n.t('api.errors.validation_failed'))
        end

        @payment.update!(external_reference: value)
      end

      def apply_paid_at!
        unless @payment.paid?
          raise PaymentCorrectionNotAllowedError.new(field: 'correction.field',
                                                     message: I18n.t('api.errors.payment_correction_not_allowed'))
        end

        parsed = parsed_timestamp(@params.value)
        if parsed.future?
          raise ValidationError.new(field: 'correction.value',
                                    message: I18n.t('api.errors.validation_failed'))
        end

        @payment.update!(paid_at: parsed)
      end

      def parsed_timestamp(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        raise ValidationError.new(field: 'correction.value', message: I18n.t('api.errors.validation_failed'))
      end

      def apply_status_code!
        target = @params.value.to_s.strip
        raise ValidationError.new(field: 'correction.value', message: I18n.t('api.errors.validation_failed')) unless
          Payment::STATUS_CODES.include?(target)

        validate_status_transition!(target)
        @payment.update!(status_code: target)
      end

      def validate_status_transition!(target)
        return validate_evidence_backed_transition!(target) if EVIDENCE_BACKED_STATUS_TRANSITIONS.key?(target)

        pair = [@payment.status_code, target]
        return if ALLOWED_STATUS_TRANSITIONS.include?(pair)

        raise PaymentCorrectionNotAllowedError.new(field: 'correction.value')
      end

      def validate_evidence_backed_transition!(target)
        required_finding_code = EVIDENCE_BACKED_STATUS_TRANSITIONS.fetch(target)
        has_matching_finding = @finding&.finding_code == required_finding_code
        has_provider_evidence = @payment.payment_events.exists?(event_type: 'payment_succeeded')
        return if has_matching_finding && has_provider_evidence

        raise PaymentCorrectionNotAllowedError.new(field: 'correction.value')
      end

      def record_event!
        @payment.payment_events.create!(event_attributes)
      end

      def event_attributes
        {
          candidate_assignment: @payment.candidate_assignment, actor: @params.actor,
          provider_code: 'admin', event_source: 'admin_correction', event_type: 'payment_corrected',
          event_key: SecureRandom.uuid, occurred_at: Time.current,
          request_id: @params.request_id, payload: event_payload
        }
      end

      def event_payload
        {
          reason: @params.reason,
          field: @params.field,
          previous_value: @previous_value,
          new_value: @params.field.present? ? @params.value.to_s : nil,
          finding_id: @finding&.public_id
        }.compact
      end

      def record_audit!
        AuditEvent.create!(audit_attributes)
      end

      def audit_attributes
        {
          actor: @params.actor, candidate: @payment.candidate_assignment.candidate,
          candidate_assignment: @payment.candidate_assignment, entity_type: 'Payment', entity_id: @payment.id,
          action_code: 'payment_corrected', metadata: event_payload,
          request_id: @params.request_id, occurred_at: Time.current
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
